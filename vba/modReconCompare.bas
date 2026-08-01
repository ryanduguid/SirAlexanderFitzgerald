Attribute VB_Name = "modReconCompare"
Option Explicit

' modReconCompare
' Keyed two-way reconciliation between two ranges — the "why doesn't the
' subledger agree to the GL" workhorse. Late-bound Scripting.Dictionary,
' so no references need adding.
' Import via VBE: File > Import File...

' Compares two two-column ranges (key, amount). Writes a "Recon Result"
' sheet listing: keys only in A, keys only in B, and keys in both where
' the amounts differ by more than tolerance. Duplicate keys within a side
' are summed before comparing (subledger detail vs GL balance pattern).
'
' Example:
'   CompareKeyedRanges Sheet1.Range("A2:B500"), Sheet2.Range("A2:B300"), 0.01
Public Sub CompareKeyedRanges( _
    ByVal rangeA As Range, _
    ByVal rangeB As Range, _
    Optional ByVal tolerance As Double = 0.005)

    Dim skippedRows As Long
    skippedRows = 0

    Dim dictA As Object, dictB As Object
    Set dictA = SumByKey(rangeA, skippedRows)
    Set dictB = SumByKey(rangeB, skippedRows)

    ' Refuse to run when a source range lives on the result sheet — the
    ' delete below would destroy caller data.
    If StrComp(rangeA.Worksheet.Name, "Recon Result", vbTextCompare) = 0 _
        Or StrComp(rangeB.Worksheet.Name, "Recon Result", vbTextCompare) = 0 Then
        Err.Raise 5, , "Source range is on the 'Recon Result' sheet - move the data or rename the sheet."
    End If

    Dim wb As Workbook
    Set wb = rangeA.Worksheet.Parent
    If wb.ProtectStructure Then
        Err.Raise 5, , "Workbook structure is protected - unprotect it before running the recon."
    End If

    ' Replace any stale result sheet from a previous run — a silently
    ' mis-named result sheet would leave old numbers looking current.
    ' Sheets (not Worksheets) so a chart sheet holding the name is caught too.
    On Error Resume Next
    Application.DisplayAlerts = False
    wb.Sheets("Recon Result").Delete
    Application.DisplayAlerts = True
    On Error GoTo 0

    ' The delete fails silently when "Recon Result" is the last visible
    ' sheet — verify the name is actually free before claiming it.
    Dim stale As Object
    On Error Resume Next
    Set stale = wb.Sheets("Recon Result")
    On Error GoTo 0
    If Not stale Is Nothing Then
        Err.Raise 5, , "Cannot replace 'Recon Result' (it is the only visible sheet)."
    End If

    Dim ws As Worksheet
    Set ws = wb.Worksheets.Add
    ws.Name = "Recon Result"

    ws.Range("A1:D1").Value = Array("Key", "Side A", "Side B", "Difference")
    ws.Range("A1:D1").Font.Bold = True

    Dim outRow As Long
    outRow = 2

    Dim k As Variant, amtA As Double, amtB As Double, diff As Double
    ' Keys in A (matched and A-only)
    For Each k In dictA.Keys
        amtA = dictA(k)
        amtB = 0#
        If dictB.Exists(k) Then amtB = dictB(k)
        diff = amtA - amtB
        If Abs(diff) > tolerance Then
            ws.Cells(outRow, 1).Value = k
            ws.Cells(outRow, 2).Value = amtA
            If dictB.Exists(k) Then ws.Cells(outRow, 3).Value = amtB
            ws.Cells(outRow, 4).Value = diff
            outRow = outRow + 1
        End If
    Next k
    ' Keys only in B
    For Each k In dictB.Keys
        If Not dictA.Exists(k) Then
            amtB = dictB(k)
            If Abs(amtB) > tolerance Then
                ws.Cells(outRow, 1).Value = k
                ws.Cells(outRow, 3).Value = amtB
                ws.Cells(outRow, 4).Value = -amtB
                outRow = outRow + 1
            End If
        End If
    Next k

    ws.Range(ws.Cells(2, 2), ws.Cells(outRow - 1, 4)).NumberFormat = "#,##0.00;(#,##0.00);""-"""
    ws.Columns("A:D").AutoFit

    ws.Cells(outRow + 1, 1).Value = "Items: " & (outRow - 2) & _
        "   Skipped rows (errors/blanks): " & skippedRows & _
        "   Tolerance: " & tolerance & _
        "   Run: " & Format$(Now, "d mmm yyyy hh:mm")
End Sub

' Sums a two-column (key, amount) range into a dictionary, keyed on the
' trimmed text of column 1. Rows with error values (#N/A, #REF!...), blank
' keys, or non-numeric amounts are skipped and counted, not crashed on.
Private Function SumByKey(ByVal source As Range, ByRef skippedRows As Long) As Object
    Dim dict As Object
    Set dict = CreateObject("Scripting.Dictionary")
    dict.CompareMode = vbTextCompare

    Dim r As Long, k As String, keyVal As Variant, v As Variant
    For r = 1 To source.Rows.Count
        keyVal = source.Cells(r, 1).Value
        v = source.Cells(r, 2).Value
        If IsError(keyVal) Or IsError(v) Then
            skippedRows = skippedRows + 1
        Else
            k = Trim$(CStr(keyVal))
            If Len(k) > 0 And IsNumeric(v) Then
                If dict.Exists(k) Then
                    dict(k) = dict(k) + CDbl(v)
                Else
                    dict.Add k, CDbl(v)
                End If
            ElseIf Len(k) > 0 Or Not IsEmpty(v) Then
                ' counts bad-amount rows AND blank-key rows carrying data;
                ' fully empty rows (oversized selections) stay uncounted
                skippedRows = skippedRows + 1
            End If
        End If
    Next r

    Set SumByKey = dict
End Function
