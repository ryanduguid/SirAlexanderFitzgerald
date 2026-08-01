// Fx.AUFinancialYear
// Australian financial year (1 July – 30 June) attributes for any date.
// Returns a record: Label ("FY2026"), StartDate, EndDate, EndYear.
//
// Usage:
//   Fx.AUFinancialYear(#date(2026, 3, 15))[Label]   // "FY2026"
//   Fx.AUFinancialYear(#date(2026, 8, 1))[Label]    // "FY2027"
// Add an FY column to a table:
//   Table.AddColumn(t, "FY", each Fx.AUFinancialYear([Date])[Label], type text)
let
    AUFinancialYear = (d as date) as record =>
        let
            endYear = Date.Year(d) + (if Date.Month(d) >= 7 then 1 else 0)
        in
            [
                Label = "FY" & Text.From(endYear),
                StartDate = #date(endYear - 1, 7, 1),
                EndDate = #date(endYear, 6, 30),
                EndYear = endYear
            ]
in
    AUFinancialYear
