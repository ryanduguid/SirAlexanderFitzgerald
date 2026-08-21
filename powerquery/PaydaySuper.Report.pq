/*
PaydaySuper.Report

Imports the fixed 18-column CSV contract emitted by payday-super-checker.
It is deliberately an adapter, not an assessment: source verdicts, caveats,
notes, unassessable_between and producer amounts remain authoritative.  The
producer's full-width terminal employee_id = NOTE row is excluded from data;
its notes field is exposed as table metadata [PaydaySuperProvenance].

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
        fileBinary = File.Contents(FilePath),
        lines = Lines.FromBinary(fileBinary, null, null, 65001),
        HeaderLine = if List.IsEmpty(lines) then
            error Error.Record("PaydaySuper.Report", "Missing required header", "The report has no header row.")
            else Text.TrimStart(List.First(lines), {Character.FromNumber(65279)}),
        // Producer header names do not contain quoted commas. Measure this
        // named header before Csv.Document so a future extra field is allowed
        // while a short or over-wide data row still fails deterministically.
        HeaderNames = Text.Split(HeaderLine, ","),
        DuplicateHeaders = List.Select(
            List.Distinct(HeaderNames),
            (header as text) as logical =>
                List.Count(List.Select(HeaderNames, each _ = header)) > 1
        ),
        DuplicateChecked = if List.IsEmpty(DuplicateHeaders) then HeaderNames else
            error Error.Record(
                "PaydaySuper.Report",
                "Duplicate header",
                "Duplicate header names are not valid: " & Text.Combine(DuplicateHeaders, ", ")
            ),
        Shaped = Csv.Document(
            fileBinary,
            [
                Delimiter = ",",
                Columns = List.Count(DuplicateChecked),
                Encoding = 65001,
                QuoteStyle = QuoteStyle.Csv,
                ExtraValues = ExtraValues.Error
            ]
        ),
        Promoted = Table.PromoteHeaders(Shaped, [PromoteAllScalars = true]),
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
        NoteRows = Table.SelectRows(Indexed, each [employee_id] = "NOTE"),
        NoteCount = Table.RowCount(NoteRows),
        TerminalNote = if NoteCount = 0 then
            error Error.Record(
                "PaydaySuper.Report",
                "Missing terminal NOTE provenance",
                "The producer report must end with one employee_id = NOTE row."
            )
            else if NoteCount <> 1 or NoteRows{0}[__source_index] <> Table.RowCount(Indexed) - 1 then
            error Error.Record(
                "PaydaySuper.Report",
                "Malformed report row",
                "The employee_id = NOTE row must occur exactly once and be terminal."
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
        DataRows = Table.SelectRows(Indexed, each [employee_id] <> "NOTE"),
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
        Result = Table.RemoveColumns(Buffered, {"__source_index"})
    in
        Value.ReplaceMetadata(Result, [PaydaySuperProvenance = ProvenanceChecked])
in
    PaydaySuperReport
