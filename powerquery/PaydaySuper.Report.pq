/*
PaydaySuper.Report

Imports the fixed 18-column CSV contract emitted by payday-super-checker.
It is deliberately an adapter, not an assessment: source verdicts, caveats,
notes, unassessable_between and producer amounts remain authoritative.  The
producer's full-width terminal record has employee_id = NOTE, provenance in
notes and blank values in every other contract field.  Only that shape is
excluded from data; its notes field is exposed as table metadata
[PaydaySuperProvenance].

All fixtures in this repository are fabricated.  Use a real report only from
an approved location outside this repository.
*/
let
    PaydaySuperReport = (FilePath as text) as table =>
    let
        RequiredHeaders = {
            "row", "employee_id", "qe_day", "pathway", "due_date", "verdict",
            "days_late", "lateness_measured_to", "sg_amount", "final_shortfall",
            "notional_earnings", "uplift_best_case", "uplift_worst_case",
            "sgc_estimate_low", "sgc_estimate_high", "caveats", "notes",
            "unassessable_between"
        },
        AmountHeaders = {
            "sg_amount", "final_shortfall", "notional_earnings",
            "uplift_best_case", "uplift_worst_case", "sgc_estimate_low",
            "sgc_estimate_high"
        },
        TextHeaders = List.Difference(RequiredHeaders, AmountHeaders),
        // Read one stable snapshot. The width scan and Csv.Document must see
        // identical bytes even if the producer replaces the file mid-refresh.
        fileBinary = Binary.Buffer(File.Contents(FilePath)),
        CsvText = Text.TrimStart(
            Text.FromBinary(fileBinary, TextEncoding.Utf8),
            {Character.FromNumber(65279)}
        ),
        CsvCharacters = Text.ToList(CsvText),
        CarriageReturn = Character.FromNumber(13),
        LineFeed = Character.FromNumber(10),
        QuoteCharacter = Character.FromNumber(34),
        // Csv.Document pads short records with nulls, so its Columns option
        // cannot distinguish an absent final field from a present empty one.
        // Count CSV fields with the same quote-after-delimiter semantics first;
        // record separators inside quoted values do not end a record.
        CsvWidthScan = List.Accumulate(
            List.Positions(CsvCharacters),
            [
                InQuotes = false,
                SkipEscapedQuote = false,
                SkipLineFeed = false,
                AtFieldStart = true,
                FieldCount = 1,
                Widths = {},
                EndedWithRecordSeparator = false
            ],
            (state as record, position as number) as record =>
                let
                    character = CsvCharacters{position},
                    nextCharacter = if position + 1 < List.Count(CsvCharacters) then
                        CsvCharacters{position + 1}
                        else null,
                    activeState = if state[SkipLineFeed] and character <> LineFeed then
                        Record.TransformFields(state, {{"SkipLineFeed", each false}})
                        else state
                in
                    if state[SkipLineFeed] and character = LineFeed then
                        Record.TransformFields(state, {{"SkipLineFeed", each false}})
                    else if activeState[SkipEscapedQuote] then
                        Record.TransformFields(
                            activeState,
                            {
                                {"SkipEscapedQuote", each false},
                                {"EndedWithRecordSeparator", each false}
                            }
                        )
                    else if activeState[InQuotes] then
                        if character = QuoteCharacter and nextCharacter = QuoteCharacter then
                            Record.TransformFields(
                                activeState,
                                {
                                    {"SkipEscapedQuote", each true},
                                    {"EndedWithRecordSeparator", each false}
                                }
                            )
                        else if character = QuoteCharacter then
                            Record.TransformFields(
                                activeState,
                                {
                                    {"InQuotes", each false},
                                    {"EndedWithRecordSeparator", each false}
                                }
                            )
                        else
                            Record.TransformFields(
                                activeState,
                                {{"EndedWithRecordSeparator", each false}}
                            )
                    else if activeState[AtFieldStart] and character = QuoteCharacter then
                        Record.TransformFields(
                            activeState,
                            {
                                {"InQuotes", each true},
                                {"AtFieldStart", each false},
                                {"EndedWithRecordSeparator", each false}
                            }
                        )
                    else if character = "," then
                        Record.TransformFields(
                            activeState,
                            {
                                {"AtFieldStart", each true},
                                {"FieldCount", each _ + 1},
                                {"EndedWithRecordSeparator", each false}
                            }
                        )
                    else if character = CarriageReturn or character = LineFeed then
                        Record.TransformFields(
                            activeState,
                            {
                                {"SkipLineFeed", each character = CarriageReturn},
                                {"AtFieldStart", each true},
                                {"FieldCount", each 1},
                                {"Widths", each _ & {activeState[FieldCount]}},
                                {"EndedWithRecordSeparator", each true}
                            }
                        )
                    else
                        Record.TransformFields(
                            activeState,
                            {
                                {"AtFieldStart", each false},
                                {"EndedWithRecordSeparator", each false}
                            }
                        )
        ),
        CsvRecordWidths = if List.IsEmpty(CsvCharacters) then
            {}
            else if CsvWidthScan[EndedWithRecordSeparator] then
                CsvWidthScan[Widths]
            else
                CsvWidthScan[Widths] & {CsvWidthScan[FieldCount]},
        HeaderWidth = if List.IsEmpty(CsvRecordWidths) then
            error Error.Record(
                "PaydaySuper.Report",
                "Missing required header",
                "The report has no header row."
            )
            else CsvRecordWidths{0},
        MalformedRecordNumbers = List.Transform(
            List.Select(
                List.Positions(CsvRecordWidths),
                each CsvRecordWidths{_} <> HeaderWidth
            ),
            each _ + 1
        ),
        RecordWidthsChecked = if List.IsEmpty(MalformedRecordNumbers) then
            HeaderWidth
            else error Error.Record(
                "PaydaySuper.Report",
                "Malformed report row",
                "Every CSV record must contain exactly " & Text.From(HeaderWidth) &
                    " fields; malformed record(s): " &
                    Text.Combine(List.Transform(MalformedRecordNumbers, Text.From), ", ") & "."
            ),
        Shaped = Csv.Document(
            fileBinary,
            [
                Delimiter = ",",
                Columns = RecordWidthsChecked,
                Encoding = 65001,
                QuoteStyle = QuoteStyle.Csv,
                ExtraValues = ExtraValues.Error
            ]
        ),
        HeaderNames = if Table.RowCount(Shaped) = 0 then
            error Error.Record("PaydaySuper.Report", "Missing required header", "The report has no header row.")
            else List.Transform(
                Record.FieldValues(Shaped{0}),
                each if _ = null then "" else Text.From(_)
            ),
        DuplicateHeaders = List.Select(
            List.Distinct(HeaderNames),
            (header as text) as logical =>
                List.Count(List.Select(HeaderNames, each _ = header)) > 1
        ),
        DuplicateChecked = if List.IsEmpty(DuplicateHeaders) then Shaped else
            error Error.Record(
                "PaydaySuper.Report",
                "Duplicate header",
                "Duplicate header names are not valid: " & Text.Combine(DuplicateHeaders, ", ")
            ),
        Promoted = Table.PromoteHeaders(DuplicateChecked, [PromoteAllScalars = true]),
        MissingHeaders = List.Difference(RequiredHeaders, Table.ColumnNames(Promoted)),
        HeadersChecked = if List.IsEmpty(MissingHeaders) then Promoted else
            error Error.Record(
                "PaydaySuper.Report",
                "Missing required header",
                "Required header names are missing or renamed: " & Text.Combine(MissingHeaders, ", ")
            ),
        // Ignore producer additions only after all named contract fields exist.
        Projected = Table.SelectColumns(HeadersChecked, RequiredHeaders, MissingField.Error),
        Indexed = Table.AddIndexColumn(Projected, "__source_index", 0, 1, Int64.Type),
        TerminalBlankFields = List.RemoveItems(RequiredHeaders, {"employee_id", "notes"}),
        IsBlank = (value as any) as logical =>
            value = null or Text.Trim(Text.From(value)) = "",
        IsTerminalNoteCandidate = (current as record) as logical =>
            current[employee_id] = "NOTE" and
                List.AllTrue(List.Transform(
                    TerminalBlankFields,
                    (column as text) as logical => IsBlank(Record.Field(current, column))
                )),
        NoteRows = Table.SelectRows(Indexed, each IsTerminalNoteCandidate(_)),
        NoteCount = Table.RowCount(NoteRows),
        TerminalNote = if NoteCount = 0 then
            error Error.Record(
                "PaydaySuper.Report",
                "Missing terminal NOTE provenance",
                "The producer report must end with one full-shape employee_id = NOTE provenance record."
            )
            else if NoteCount <> 1 or NoteRows{0}[__source_index] <> Table.RowCount(Indexed) - 1 then
            error Error.Record(
                "PaydaySuper.Report",
                "Malformed report row",
                "The full-shape employee_id = NOTE provenance record must occur exactly once and be terminal."
            )
            else NoteRows{0},
        Provenance = TerminalNote[notes],
        ProvenanceChecked = if Provenance = null or Text.Trim(Text.From(Provenance)) = "" then
            error Error.Record(
                "PaydaySuper.Report",
                "Missing terminal NOTE provenance",
                "The terminal NOTE row must provide provenance in its notes field."
            )
            else Text.From(Provenance),
        DataRows = Table.SelectRows(Indexed, each not IsTerminalNoteCandidate(_)),
        MandatoryDataFields = {"row", "employee_id", "qe_day", "pathway", "verdict"},
        MalformedRows = Table.SelectRows(
            DataRows,
            each
                let current = _ in
                    List.AnyTrue(List.Transform(
                        MandatoryDataFields,
                        (column as text) as logical =>
                            let value = Record.Field(current, column) in
                                value = null or Text.Trim(Text.From(value)) = ""
                    ))
        ),
        DataChecked = if Table.RowCount(MalformedRows) = 0 then DataRows else
            error Error.Record(
                "PaydaySuper.Report",
                "Malformed report row",
                "Each contribution row requires row, employee_id, qe_day, pathway and verdict."
            ),
        TextTyped = Table.TransformColumns(
            DataChecked,
            List.Transform(
                TextHeaders,
                (column as text) => {column, each if _ = null then null else Text.From(_), type nullable text}
            )
        ),
        ParseAmount = (value as nullable any, column as text) as nullable number =>
            let
                raw = if value = null then "" else Text.Trim(Text.From(value)),
                parsed = if raw = "" then [HasError = false, Value = null] else
                    try Number.FromText(raw, "en-AU")
            in
                if parsed[HasError] then
                    error Error.Record(
                        "PaydaySuper.Report",
                        "Invalid amount",
                        "Column " & column & " must be blank or an en-AU number."
                    )
                else parsed[Value],
        AmountTyped = List.Accumulate(
            AmountHeaders,
            TextTyped,
            (state as table, column as text) as table =>
                Table.TransformColumns(
                    state,
                    {{column, each ParseAmount(_, column), type nullable number}}
                )
        ),
        // Force producer amount validation before a caller can count or join
        // the table without touching each amount column.
        Buffered = Table.Buffer(AmountTyped),
        Result = Table.RemoveColumns(Buffered, {"__source_index"}),
        // Metadata record fields are lazy in M. Make ordinary table use depend
        // on the provenance text so absent or malformed provenance cannot be
        // observed only when a caller happens to inspect Value.Metadata.
        ValidatedResult = if Text.Length(ProvenanceChecked) >= 0 then Result else
            error Error.Record(
                "PaydaySuper.Report",
                "Missing terminal NOTE provenance",
                "Provenance validation produced an impossible state."
            )
    in
        Value.ReplaceMetadata(ValidatedResult, [PaydaySuperProvenance = ProvenanceChecked])
in
    PaydaySuperReport
