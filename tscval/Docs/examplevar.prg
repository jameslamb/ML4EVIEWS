'eq_T.tscval

wfcreate q 1990 2020
series x = @nrnd+5
series y = @nrnd+9
series z = @nrnd+7

var var01.LS 1 2 LOG(X) LOG(Y)@ C @LAG(LOG(Z ),1) @TREND 
equation eq01.LS dlog(x) c dlog(y) d(z)
eq01.tscval(H=0.4, ERR="MAE MSE",SAMPLE = "2006Q1 2015Q4")
var01.tscval(SAMPLE="2006Q1 2015Q4", H=0.4, ERR = "MAE MSE")


