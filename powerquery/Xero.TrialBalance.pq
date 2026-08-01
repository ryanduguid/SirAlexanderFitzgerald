// Xero.TrialBalance
// Parse a Xero Trial Balance CSV export into a typed table.
//
// Handles three traps in Xero's export format:
//   1. Metadata rows above the real header (report title, entity, date).
//      Csv.Document infers column count from the FIRST row — a one-field
//      title row would collapse the whole file to one column — so the header
//      row is located first and its width passed in explicitly.
//   2. Two column pairs with different meanings: "Debit"/"Credit" hold the
//      current-period MOVEMENT, "YTD Debit"/"YTD Credit" hold the AS-AT
//      balances, and a full export carries both. Default takes the YTD
//      (as-at) pair when present — the balances a trial balance is loaded
//      for — else the period pair. Pass useYTD = true to require the YTD
//      pair, useYTD = false to take the period pair; either explicit
//      choice errors when the export lacks that pair.
//   3. The trailing Total row (dropped; recompute totals, don't trust them).
//
// Splits the leading account code out of "090 - Business Bank Account"
// style names, forcing the code to text so leading zeros survive. A code
// is alphanumeric, at most 10 characters, with at least one digit ("090",
// "GST1") — a purely alphabetic prefix ("Interest - Bank") is part of the
// name, not a code.
//
// Usage: Xero.TrialBalance("C:\exports\entity-tb-2026-06-30-accrual.csv")
//        Xero.TrialBalance(path, false)   // period movement, not as-at
// Check after load (tolerance, not exact = — the sums are IEEE doubles):
//   Number.Abs(List.Sum(result[Debit]) - List.Sum(result[Credit])) < 0.005
let
    TrialBalance = (FilePath as text, optional useYTD as nullable logical) as table =>
        let
            fileBinary = File.Contents(FilePath),
            // Locate the header line and measure its width BEFORE parsing,
            // so the one-field title row can't collapse the column count.
            // The header is the line whose FIRST FIELD is exactly "Account"
            // — a prefix match would be hijacked by an entity name like
            // "Accountable Plumbing Pty Ltd" on the metadata rows above.
            lines = Lines.FromBinary(fileBinary, null, null, 65001),
            headerLines = List.Select(
                lines,
                each Text.StartsWith(Text.TrimStart(_), "Account,") or Text.Trim(_) = "Account"
            ),
            headerLine =
                if List.IsEmpty(headerLines) then
                    error Error.Record(
                        "Xero.TrialBalance",
                        "Header row not found",
                        "No line has ""Account"" as its first field — not a Xero TB export, or the format changed."
                    )
                else
                    List.First(headerLines),
            columnCount = List.Count(Text.Split(headerLine, ",")),
            Raw = Csv.Document(
                fileBinary,
                [Delimiter = ",", Columns = columnCount, Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
            ),
            Indexed = Table.AddIndexColumn(Raw, "__idx", 0, 1, Int64.Type),
            // same header test as the raw-lines pass above (first cell
            // exactly "Account"), so both passes agree on the header row
            HeaderMatches = Table.SelectRows(
                Indexed,
                each Text.Trim(Text.From([Column1] ?? "")) = "Account"
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
            // Choose ONE debit/credit pair. Debit/Credit = period movement,
            // YTD Debit/YTD Credit = as-at balances. Null (the default)
            // prefers the as-at pair; explicit true/false demands its pair.
            cols = Table.ColumnNames(Promoted),
            hasPeriod = List.Contains(cols, "Debit") and List.Contains(cols, "Credit"),
            hasYTD = List.Contains(cols, "YTD Debit") and List.Contains(cols, "YTD Credit"),
            takeYTD =
                if useYTD = true then
                    if hasYTD then true
                    else error Error.Record("Xero.TrialBalance", "YTD columns not found",
                        "useYTD = true but the export has no YTD Debit/YTD Credit columns.")
                else if useYTD = false then
                    if hasPeriod then false
                    else error Error.Record("Xero.TrialBalance", "Period columns not found",
                        "useYTD = false but the export has no Debit/Credit columns.")
                else
                    hasYTD,
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
            // Culture pinned to en-AU: Xero CSVs always use "." decimal, but
            // an unpinned Number.From follows the machine locale — de-DE
            // reads "15234.50" as 1523450, fr-FR fails into the 0 fallback.
            Typed = Table.TransformColumns(
                Body,
                {
                    {"Debit", each (try Number.From(_, "en-AU") otherwise 0) ?? 0, type number},
                    {"Credit", each (try Number.From(_, "en-AU") otherwise 0) ?? 0, type number}
                }
            ),
            // "090 - Business Bank Account" -> code "090", name "Business Bank Account".
            // A code is alphanumeric with at least one digit, max 10 chars
            // ("090", "GST1", MYOB-migration codes); a purely alphabetic
            // prefix ("Interest - Bank") stays in the name. Rows without a
            // code keep a null code.
            WithCode = Table.AddColumn(
                Typed,
                "AccountCode",
                each
                    let
                        candidate = Text.BeforeDelimiter([Account], " - "),
                        isCode = candidate <> [Account]
                            and Text.Length(candidate) <= 10
                            and Text.Select(candidate, {"0".."9"}) <> ""
                            and Text.Select(candidate, {"0".."9", "A".."Z", "a".."z"}) = candidate
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
