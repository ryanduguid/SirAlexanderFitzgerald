// Fx.AUFinancialYear
// Australian financial year (1 July – 30 June) attributes for any date.
// Returns a record: Label ("FY2026"), StartDate, EndDate, EndYear.
//
// Date, datetime and datetimezone values are accepted — Excel hands back
// date cells as datetime unless a Changed Type step has already run. A
// datetimezone is read at the wall clock it carries: the offset is dropped,
// never converted, so 9am +10:00 on 1 July is 1 July on a Sydney desktop and
// on a UTC-hosted scheduled refresh alike. Text is parsed as an Australian
// date, so "01/07/2026" is 1 July whatever the machine's locale; a number is
// read as an Excel serial. A null date returns a record of nulls, so a blank
// cell leaves a blank FY on that row rather than an error.
//
// Usage:
//   Fx.AUFinancialYear(#date(2026, 3, 15))[Label]   // "FY2026"
//   Fx.AUFinancialYear(#date(2026, 8, 1))[Label]    // "FY2027"
// Add an FY column to a table:
//   Table.AddColumn(t, "FY", each Fx.AUFinancialYear([Date])[Label], type text)
let
    AUFinancialYear = (d as any) as record =>
        let
            // Date.From on a datetimezone returns the date of the value's
            // LOCAL equivalent, so the host's zone decides the answer: 9am
            // +10:00 on 1 July 2026 is FY2027 on a Sydney desktop and
            // FY2026 on a UTC-hosted scheduled refresh, and the two only
            // disagree on financial-year boundaries. Drop the offset first
            // and the wall clock as supplied decides instead.
            normalised = if Value.Is(d, type datetimezone) then DateTimeZone.RemoveZone(d) else d,
            asDate = Date.From(normalised, "en-AU"),
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
