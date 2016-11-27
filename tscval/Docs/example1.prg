'Motivation: Estimate & cross-validate a few models of US industrial production.

'##########################################################################################################

	mode quiet
	setmaxerrs 1
	logmode logmsg
		
	'Create workfile
	wfcreate(wf=CV_EXAMPLE, page = DATA_M) q 1920 2020 'wf=CV_EXAMPLE, 
	
	'Fetch data
	fetch(d=FRED) INDPRO CPIAUCSL
	
	'Estimate a few differerent models
	equation eq_01.ls d(indpro) c ar(1)
	equation eq_02.ls d(indpro) c ar(1) ar(2) ma(1)
	equation eq_03.ls indpro c ar(1)
	
	'Cross validate each
	%eqs = @wlookup("EQ_*", "equation")
	for %eq {%eqs}
		{%eq}.tscval(ERR="MAE MSE MAPE medSE medAE SMAPE medPE medSPE", KEEP_MATS=t, VAR_FORM=CURRENT)
	next
		

'##########################################################################################################


