Attribute VB_Name = "modWorkpaperFormat"
Option Explicit

' modWorkpaperFormat
' Standard workpaper presentation: header block, prepared-by stamp, and
' number formatting that matches how a reviewer expects a workpaper to read.
' Import via VBE: File > Import File... (or drag into the Modules folder).

' Writes the standard four-line workpaper header at the top of a sheet:
'   entity name, workpaper title, period end, prepared-by / date stamp.
' Inserts rows so existing content is pushed down, not overwritten.
Public Sub ApplyWorkpaperHeader( _
    ByVal ws As Worksheet, _
    ByVal entityName As String, _
    ByVal wpTitle As String, _
    ByVal periodEnd As Date, _
    ByVal preparedBy As String)

    ws.Rows("1:5").Insert Shift:=xlDown

    With ws
        .Range("A1").Value = entityName
        .Range("A2").Value = wpTitle
        .Range("A3").Value = "For the period ended " & Format$(periodEnd, "d mmmm yyyy")
        .Range("A4").Value = "Prepared by: " & preparedBy & "    Date: " & Format$(Date, "d mmm yyyy")

        .Range("A1:A2").Font.Bold = True
        .Range("A1").Font.Size = 12
        .Range("A4").Font.Italic = True
        .Range("A5:H5").Borders(xlEdgeBottom).LineStyle = xlContinuous
    End With
End Sub

' Adds a reviewer sign-off line below the last used row.
Public Sub AddReviewerLine(ByVal ws As Worksheet)
    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, "A").End(xlUp).Row

    ws.Cells(lastRow + 2, 1).Value = "Reviewed by: ______________    Date: ____________"
    ws.Cells(lastRow + 2, 1).Font.Italic = True
End Sub

' Applies accounting number format (thousands separator, bracketed negatives,
' dash for zero) to a range — the format reviewers expect on workpapers.
Public Sub FormatAsAccounting(ByVal target As Range)
    target.NumberFormat = "#,##0.00;(#,##0.00);""-"""
End Sub

' Freezes panes below the header block (the 5 rows ApplyWorkpaperHeader
' writes). Pass headerRows = 6 if your data keeps its own column-header row
' directly under the block. Clears any existing freeze AND split first
' (both silently hijack the freeze position), and pins the scroll to the
' top so the freeze anchors where the selection says, not where the window
' happened to be scrolled.
Public Sub FreezeBelowHeader(ByVal ws As Worksheet, Optional ByVal headerRows As Long = 5)
    ws.Activate
    With ActiveWindow
        .FreezePanes = False
        .Split = False
        .ScrollRow = 1
        .ScrollColumn = 1
    End With
    ws.Cells(headerRows + 1, 1).Select
    ActiveWindow.FreezePanes = True
End Sub
