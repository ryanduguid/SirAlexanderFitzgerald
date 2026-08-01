// Xero.TrialBalance
// Parse a Xero Trial Balance CSV export into a typed table.
//
// Handles three traps in Xero's export format:
//   1. Metadata rows above the real header (report title, entity, date).
//      Csv.Document infers column count from the FIRST row — a one-field
//      title row would collapse the whole file to one column — so the header
//      row is located first and its width passed in explicitly.
//   2. Column variants: some exports carry "YTD Debit"/"YTD Credit" instead
//      of — or alongside — "Debit"/"Credit". Default takes the period pair
//      when both exist; pass useYTD = true to take the YTD pair.
//   3. The trailing Total row (dropped; recompute totals, don't trust them).
//
// Splits the leading account code out of "090 - Business Bank Account"
// style names, forcing the code to text so leading zeros survive.
//
// Usage: Xero.TrialBalance("C:\exports\entity-tb-2026-06-30-accrual.csv")
//        Xero.TrialBalance(path, true)   // use YTD columns
// Check after load: List.Sum(result[Debit]) = List.Sum(result[Credit])
let
    TrialBalance = (FilePath as text, optional useYTD as nullable logical) as table =>
        let
            fileBinary = File.Contents(FilePath),
            // Locate the header line and measure its width BEFORE parsing,
            // so the one-field title row can't collapse the column count.
            lines = Lines.FromBinary(fileBinary, null, null, 65001),
            headerLines = List.Select(lines, each Text.StartsWith(Text.Trim(_), "Account")),
            headerLine =
                if List.IsEmpty(headerLines) then
                    error Error.Record(
                        "Xero.TrialBalance",
                        "Header row not found",
                        "No line starts with ""Account"" — not a Xero TB export, or the format changed."
                    )
                else
                    List.First(headerLines),
            columnCount = List.Count(Text.Split(headerLine, ",")),
            Raw = Csv.Document(
                fileBinary,
                [Delimiter = ",", Columns = columnCount, Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
            ),
            Indexed = Table.AddIndexColumn(Raw, "__idx", 0, 1, Int64.Type),
            // same predicate as the raw-lines pass above, so both passes
            // agree on what counts as the header row
            HeaderMatches = Table.SelectRows(
                Indexed,
                each Text.StartsWith(Text.Trim(Text.From([Column1] ?? "")), "Account")
            )[__idx],
            HeaderIdx =
                if List.IsEmpty(HeaderMatches) then
                    error Error.Record(
                        "Xero.TrialBalance",
                        "Header row not found",
                        "Header line detected in raw text but not in the parsed CSV — format changed."
                    )
                else
                    List.Min(HeaderMatches),
            Sliced = Table.RemoveFirstN(Raw, HeaderIdx),
            Promoted = Table.PromoteHeaders(Sliced, [PromoteAllScalars = true]),
            // Choose ONE debit/credit pair. Period pair by default; YTD on
            // request or when it's the only pair present.
            cols = Table.ColumnNames(Promoted),
            hasPeriod = List.Contains(cols, "Debit") and List.Contains(cols, "Credit"),
            hasYTD = List.Contains(cols, "YTD Debit") and List.Contains(cols, "YTD Credit"),
            takeYTD =
                if useYTD = true then
                    if hasYTD then true
                    else error Error.Record("Xero.TrialBalance", "YTD columns not found",
                        "useYTD = true but the export has no YTD Debit/YTD Credit columns.")
                else
                    not hasPeriod and hasYTD,
            Selected =
                if not hasPeriod and not hasYTD then
                    error Error.Record("Xero.TrialBalance", "Debit/Credit columns not found",
                        "Expected Debit/Credit or YTD Debit/YTD Credit after the header row.")
                else if takeYTD then
                    Table.RenameColumns(
                        Table.RemoveColumns(Promoted, {"Debit", "Credit"}, MissingField.Ignore),
                        {{"YTD Debit", "Debit"}, {"YTD Credit", "Credit"}}
                    )
                else
                    Table.RemoveColumns(Promoted, {"YTD Debit", "YTD Credit"}, MissingField.Ignore),
            // Drop blank rows and Xero's Total row
            Body = Table.SelectRows(
                Selected,
                each
                    Text.Trim(Text.From([Account] ?? "")) <> ""
                    and not Text.StartsWith(Text.Trim(Text.From([Account])), "Total")
            ),
            Typed = Table.TransformColumns(
                Body,
                {
                    {"Debit", each (try Number.From(_) otherwise 0) ?? 0, type number},
                    {"Credit", each (try Number.From(_) otherwise 0) ?? 0, type number}
                }
            ),
            // "090 - Business Bank Account" -> code "090", name "Business Bank Account".
            // Rows without the "code - name" pattern keep a null code.
            WithCode = Table.AddColumn(
                Typed,
                "AccountCode",
                each
                    let
                        candidate = Text.BeforeDelimiter([Account], " - "),
                        isCode = candidate <> [Account]
                            and Text.Length(candidate) > 0
                            and Text.Select(candidate, {"0".."9"}) = candidate
                    in
                        if isCode then candidate else null,
                type nullable text
            ),
            WithName = Table.AddColumn(
                WithCode,
                "AccountName",
                each if [AccountCode] <> null then Text.AfterDelimiter([Account], " - ") else [Account],
                type text
            )
        in
            WithName
in
    TrialBalance
