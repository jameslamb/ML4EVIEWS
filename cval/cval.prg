'Author: James Lamb, Abbott Economics

'Motivation: Perform rolling time-series corss validation.

'Description: 
' 	Program which takes an equation, rolls teh sample, keeps producing forecasts,
' 	then stacks up vectors by horizon and computes errors at different horizons.
' 	Returns a few objects in the wf:
'		1. T_ACC --> a table with the eq name and error (see below) by forecast horizon

'##########################################################################################################
'##########################################################################################################
'##########################################################################################################
setmaxerrs 1
mode quiet
logmode logmsg
logmsg

'NOTE: Currently only supports equation objects (no VARs)

	logmsg
	logmsg --- BEGINNING ROLL_FCST ---
	logmsg
	
		tic
		
		'Get params
		
		'---- Passed in ------'
		%eq = {%0} 'equation object to work with
		%short_end = {%1} 'end of the shortest sample to forecast over
		%longest_smpl = {%2} 'What is the longest sample to estiamte? e.g. "1990 2015M10"
		%err_measure = {%3} 'what error measure do you prefer? 
			'Valid options:
'				a. "MSE" = mean squared error
'				b. "MAE" = mean absolute error
'				c. "RMSE" = root mean squuared error
'				d. "MSFE" = mean squared forecast error
'				e. "MAPE" = mean absolute percent error
'				f. "MPE" = mean percentage error
'				g. "MSPE" = mean squared percentage error
'				h. "RMSPE" = root mean squared percentage error
'				i. "SIGN" = count of the number of times the forecast guess the correct direction of change
'				j. "SIGN_PERCENT" = percent of the times that we guessed the sign of the forecast correctly
			
		%keep_fcst = {%4} 'Set to "TRUE" or "T" to avoid deleting the forecast series
		
		'--- Environment ---'
		%freq = @pagefreq 'page frequency
		%pagesmpl = @pagesmpl
		%pagename = @pagename
		%command = {%eq}.@command 'command to re-estimate (with all the same options)
		
		pageselect {%pagename}
		{%eq}.makeregs g1
		%base_dep = @word(g1.@depends,1) 'dependent variable WITHOUT transformations
		delete g1
				
		%start_est = @word(%longest_smpl,1) 'where should estimation start?
		%end_est = @word(%longest_smpl,2) 'where should the longest estimation end?
		!tot_eqs = @dtoo(%end_est) - @dtoo(%short_end) 'number of estiamtions we'll do
		
	logmsg --- Copying over necessary stuff to a new page
	
		%newpage = "TMPAAAAA" 'give it a ridiculous name to avoid overwriting stuff
		pagecreate(page={%newpage}) {%freq} {%pagesmpl} 'give it a crazy name to minimize risk of overwriting things
		pageselect {%newpage}
		
		'Create a group of regressors and copy it over
		'NOTE: This will take only the base series. If the reg. has CPI and d(CPI), only CPI is copied
		pageselect {%pagename}
		%rgroup = "g_blahblah"
		{%eq}.makeregs {%rgroup}
			{%rgroup}.drop @trend @trend^2 log(@trend)
		copy(g=d) {%pagename}\{%rgroup} {%newpage}\{%rgroup} '(g=d) --> series only (not the group object
		
		'delete that group
		delete {%pagename}\{%rgroup}
		
		copy {%pagename}\{%eq} {%newpage}\{%eq}
		pageselect {%newpage}
		
		'---- Date format ----'
		%freq = @pagefreq
	
		if %freq = "A" then 
			%date_format = "YYYY"
		else
			if %freq = "Q" then
				%date_format = "YYYY[Q]Q"
			else
				if %freq = "M" then
					%date_format = "YYYY[M]MM"
				else
					if @wfind("W D5 D7 D", %freq) <> 0 then
						%date_format = "MM/DD/YYYY"
					endif
				endif
			endif
		endif
		
		'Return this string in a workfile object
		string date_fmt = %date_format
		
	logmsg --- Beginning rolling estimation and forecasting
		
		for !i = 0 to !tot_eqs-1
			
			'Estimate the model for this sample
			%end_est = @datestr(@dateadd(@dateval(%short_end), +{!i}, %freq), date_fmt)
			%est_smpl = %start_est + " " + %end_est
			logmsg --- Estimating {%eq} over sample %est_smpl
			
			smpl {%est_smpl}
				{%eq}.{%command} 're-estimates the equation
				
			'Forecast over all the remaining periods
			%start_fcst = @datestr(@dateadd(@dateval(%end_est), +1, %freq), date_fmt)
			
			smpl {%start_fcst} @last
				{%eq}.forecast(f=na) {%base_dep}_f_{%start_fcst}
			smpl @all
		next
			
	logmsg --- Creating Series and Vectors of Errors
	
		%lookup = %base_dep + "_F_*"
		%list = @wlookup(%lookup, "series")
		for %series {%list}
			%prefx = %base_dep + "_F_"
			
			'Absolute errors
			%error_ser = @replace(%series, %prefx, "ERR_")
			%error_vec = @replace(%series, %prefx, "V_ERR_")
			smpl @all
				series {%error_ser} = {%base_dep} - {%series} 'prediction is always of the level, not the transformation!
				vector {%error_vec} = @convert({%error_ser})
			smpl @all
			
			'Percentage errors
			%pc_error_ser = @replace(%series, %prefx, "ERR_PC_") 'percentage error
			%pc_error_vec = @replace(%series, %prefx, "V_PCERR_") 'percentage error
			smpl @all
				series {%pc_error_ser} = 100*({%base_dep} - {%series})/({%base_dep}) 'report in percentage point units (thus the *100)
				vector {%pc_error_vec} = @convert({%pc_error_ser})
			smpl @all
			
			'Sign errors
			%sign_error_ser = @replace(%series, %prefx, "ERR_SGN_") 'percentage error
			%sign_error_vec = @replace(%series, %prefx, "V_SGNERR_") 'percentage error
			smpl @all
				'Get a series of changes for the denominator
				series changes = d({%base_dep})
				changes = @recode(changes=0, 1e-03, changes) 'recode 0s to small positive (want to treat  0 as positive)
				
				'If change in fcst and change in actual are in the same direction, the sign was correct
				series {%sign_error_ser} = (({%series}- {%base_dep}(-1)) / changes) > 0 '1 if correct sign, 0 otherwise
				vector {%sign_error_vec} = @convert({%sign_error_ser})
			smpl @all
			
		next
	
	logmsg --- Collecting the n-step-ahead errors
		
		'Absolute errors
		%list = @wlookup("v_err_*", "vector")
		for %vector {%list}
			
			for !indx = 1 to @wcount(%list)
				%newvec = "e_vec_" + @str(!indx)
				if @isobject(%newvec) = 0 then
					'create them
					vector(@wcount(%list)) {%newvec} = NA
					
					'Add metadata
					%desc = "Vector of " + @str(!indx) + "-step-ahead forecasts from equation " + %eq
					{%newvec}.setattr(Description) {%desc}
					
					'Fill the first element of the vector
					{%newvec}(1) = {%vector}(!indx)
				else
					!next_row = @obs({%newvec}) + 1
					if @obs({%vector}) >= !indx then
						{%newvec}(!next_row) = {%vector}(!indx)
					endif
				endif
			next
		next
		
		'Percent errors
		%list = @wlookup("v_pcerr_*", "vector")
		for %vector {%list}
			
			for !indx = 1 to @wcount(%list)
				%newvec = "e_pcvec_" + @str(!indx)
				if @isobject(%newvec) = 0 then
					'create them
					vector(@wcount(%list)) {%newvec} = NA
					
					'Add metadata
					%desc = "Vector of " + @str(!indx) + "-step-ahead forecasts from equation " + %eq
					{%newvec}.setattr(Description) {%desc}
					
					'Fill the first element of the vector
					{%newvec}(1) = {%vector}(!indx)
				else
					!next_row = @obs({%newvec}) + 1
					if @obs({%vector}) >= !indx then
						{%newvec}(!next_row) = {%vector}(!indx)
					endif
				endif
			next
		next

		'Sign errors
		%list = @wlookup("v_sgnerr_*", "vector")
		for %vector {%list}
			
			for !indx = 1 to @wcount(%list)
				%newvec = "e_sgnvec_" + @str(!indx)
				if @isobject(%newvec) = 0 then
					'create them
					vector(@wcount(%list)) {%newvec} = NA
					
					'Add metadata
					%desc = "Vector of " + @str(!indx) + "-step-ahead forecasts from equation " + %eq
					{%newvec}.setattr(Description) {%desc}
					
					'Fill the first element of the vector
					{%newvec}(1) = {%vector}(!indx)
				else
					!next_row = @obs({%newvec}) + 1
					if @obs({%vector}) >= !indx then
						{%newvec}(!next_row) = {%vector}(!indx)
					endif
				endif
			next
		next
	
	logmsg --- Creating the Forecast Eval table
	
		table t_acc
		%err_vecs = @wlookup("e_vec_*", "vector")
		t_acc(1,3) = "STEPS AHEAD -->"
		t_acc(2,1) = "Model"
		t_acc(3,1) = %eq
		t_acc(3,2) = "Forecasts:"
		t_acc(4,1) = %eq
		%err_txt = %err_measure + ":"
		t_acc(4,2) = %err_txt
		for !col = 3 to (@wcount(%err_vecs)+2)
			
			'Assign a header to the table indicating how many steps ahead
			%head = @str(!col - 2)
			t_acc(2, !col) = %head
			
			'How many forecasts did we have at this horizon?
			%vec = "E_VEC_" + %head
			%pc_vec = "E_PCVEC_" + %head 'percentage errors
			%sign_vec = "E_SGNVEC_" + %head
			!obs = @obs({%vec})
			t_acc(3, !col) = @str(!obs)
			
			'How did they do?
			
			'Absolute errors
			!MAE = @mean(@abs({%vec}))
			!MSE = @mean(@epow({%vec},2))
			!MSFE = !MSE  'some people use different terms
			!RMSE = @sqrt(!MSE)
			
			'Percentage errors
			!MAPE = @mean(@abs({%pc_vec}))
			!MPE = @mean({%pc_vec})
			!MSPE = @mean(@epow({%pc_vec},2))
			!RMSPE = @sqrt(!MSPE)
			
			'Sign Errors
			!SIGN = @sum({%sign_vec})
			!SIGN_PERCENT = 100*(!SIGN/@obs({%sign_vec}))
			
			t_acc(4,!col) =!{%err_measure}
		next
		!cols = @columns(t_acc)
		t_acc.setformat(R3C3:R4C{!cols}) f.3 'only display three decimal places
		t_acc.setlines(R2C1:R2C{!cols}) +b 'underline the header row
		
		show t_acc
	
	logmsg --- Cleaning up intermediate forecasting variables
	
		delete e_vec_* date_fmt* err_* v_err_* *obsid*
		
		if @upper(%keep_fcst) <> "TRUE" and @upper(%keep_fcst) <> "T" then
			delete {%base_dep}_f_*
		endif
		
	logmsg --- Creating a single vector of errors
	
		'Element 1 will be 1-step-ahead MSE, element 2 will be 2-step-ahead-MSE, etc.
		!steps = @columns(t_acc) - 2
		vector(!steps) v_eq_{%err_measure} = NA
		for !col = 3 to (!steps + 2)
			!indx = !col - 2
			v_eq_{%err_measure}(!indx) = @val(t_acc(4,!col)) 'errors always in row 4
		next
		
	logmsg --- Move everything left back over to the original page
	
		copy {%newpage}\* {%pagename}\*
		pagedelete {%newpage}
		pageselect {%pagename}
		
		%elapsed = @str(@toc)
		
	logmsg
	logmsg ------ ROLL_FCST COMPLETE {%elapsed} ------
	logmsg
		
'##########################################################################################################
'##########################################################################################################
'##########################################################################################################
'===========================================References===================================================='
'
'1. http://faculty.smu.edu/tfomby/eco5385/lecture/Scoring%20Measures%20for%20Prediction%20Problems.pdf
'2. http://robjhyndman.com/hyndsight/tscvexample/
'3. http://robjhyndman.com/hyndsight/crossvalidation/


