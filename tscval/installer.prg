
'This runs if the add-in is run programmatically
addin(type="equation", proc="tscval", docs=".\Docs\tscval.txt", url="https://raw.githubusercontent.com/jameslamb/ML4EVIEWS/master/tscval/update_info.xml") ".\tscvalproc.prg"

'This will add tscval to the GUI for equation objects
addin(type="equation", menu="Perform time-series cross validation", docs=".\Docs\tscval.txt", url="https://raw.githubusercontent.com/jameslamb/ML4EVIEWS/master/tscval/update_info.xml") ".\tscval_eq.prg"


