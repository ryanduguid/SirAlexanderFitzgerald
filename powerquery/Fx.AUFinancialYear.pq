// Fx.AUFinancialYear
// Australian financial year (1 July – 30 June) attributes for any date.
// Returns a record: Label ("FY2026"), StartDate, EndDate, EndYear.
//
// Date, datetime and datetimezone values are accepted — Excel hands back
// date cells as datetime unless a Changed Type step has already run. Text is
// parsed as an Australian date, so "01/07/2026" is 1 July whatever the
// machine's locale; a number is read as an Excel serial. A null date returns
// a record of nulls, so a blank cell leaves a blank FY on that row rather
// than an error.
//
// Usage:
//   Fx.AUFinancialYear(#date(2026, 3, 15))[Label]   // "FY2026"
//   Fx.AUFinancialYear(#date(2026, 8, 1))[Label]    // "FY2027"
// Add an FY column to a table:
//   Table.AddColumn(t, "FY", each Fx.AUFinancialYear([Date])[Label], type text)
let
    AUFinancialYear = (d as any) as record =>
        let
            asDate = Date.From(d, "en-AU"),
            endYear =
                if asDate = null then
                    null
                else
                    Date.Year(asDate) + (if Date.Month(asDate) >= 7 then 1 else 0),
            result =
                if endYear = null then
                    [Label = null, StartDate = null, EndDate = null, EndYear = null]
                else
                    [
                        Label = "FY" & Text.From(endYear),
                        StartDate = #date(endYear - 1, 7, 1),
                        EndDate = #date(endYear, 6, 30),
                        EndYear = endYear
                    ]
        in
            result
in
    AUFinancialYear
