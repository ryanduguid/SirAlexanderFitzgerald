// Fx.ABNIsValid
// Validate an Australian Business Number using the ATO checksum algorithm:
// subtract 1 from the first digit, multiply the 11 digits by weights
// (10, 1, 3, 5, 7, 9, 11, 13, 15, 17, 19), sum, and check mod 89 = 0.
//
// Accepts formatted input ("51 824 753 556") and number-typed columns —
// non-digits are stripped.
// Returns false for null, for anything that isn't 11 digits after
// stripping, and for a leading zero: no ABN starts with 0, and the
// checksum alone can't reject one ("00000090000" sums to exactly 89).
// Checksum validity does not mean the ABN is registered or active — check
// ABN Lookup (abr.business.gov.au) for registration status.
//
// Usage: Fx.ABNIsValid("51 824 753 556")  // true (ATO's published example)
let
    ABNIsValid = (abn as any) as logical =>
        let
            digitsOnly = Text.Select(Text.From(abn ?? ""), {"0".."9"}),
            result =
                if Text.Length(digitsOnly) <> 11 or Text.StartsWith(digitsOnly, "0") then
                    false
                else
                    let
                        digits = List.Transform(Text.ToList(digitsOnly), Number.FromText),
                        adjusted = {digits{0} - 1} & List.Skip(digits, 1),
                        weights = {10, 1, 3, 5, 7, 9, 11, 13, 15, 17, 19},
                        total = List.Sum(
                            List.Transform({0..10}, each adjusted{_} * weights{_})
                        )
                    in
                        Number.Mod(total, 89) = 0
        in
            result
in
    ABNIsValid
