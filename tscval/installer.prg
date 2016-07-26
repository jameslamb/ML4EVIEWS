%docs = ".\Docs\tscval.pdf"
%url = "http://raw.githubusercontent.com/jameslamb/ML4EVIEWS/master/tscval/update_info.xml"
%version = "1.0.5"


addin(type="equation", proc="tscval", docs=%docs, url=%url,version={%version}) ".\tscvalproc.prg"
addin(type="var", proc="tscval", docs=%docs, url=%url,version={%version}) ".\tscvalproc.prg"
addin(type="equation", menu="Perform time-series cross validation", docs=%docs, url=%url,version={%version}) ".\tscval_eq.prg"
addin(type="VAR", menu="Perform time-series cross validation", docs=%docs, url=%url,version={%version}) ".\tscval_var.prg"
addin(type="vector", proc="tscv_score", menu="Score cross validation errors", docs=%docs, url=%url,version={%version}) ".\tscv_score.prg"
