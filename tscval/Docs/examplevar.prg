'eq_T.tscval

wfcreate q 1990 2020
series x = @nrnd+5
series y = @nrnd+9
series z = @nrnd+7

var var_eq.LS 1 2 LOG(X) LOG(Y) dlog(z) @ C @LAG(LOG(Z ),1) @TREND 

var_eq.tscval
