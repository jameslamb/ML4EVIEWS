	'This runs first when tscval() is run progammatically. It supplies defaults for unspecified arguments.
	
	'--- Conduct logic checks to make sure that TSCVAL can execute on the workfile ---'
	'--- Check 1: Check that we are on a time series page ---'
	if @pagefreq = "u" or @ispanel then
		seterr "Procedure must be run on a time-series page."
	endif
	
	'--- Check 2: Check the version ---'
	if @vernum < 9 then
		seterr "EViews version 9.0 or higher is required to run this add-in."
	endif
	
	'--- Get arguments ---'
	'--- Option 1: The full range we train and evaluate models over ---'
	if @equaloption("SAMPLE")<>"" then 
		%fullsample  = @equaloption("SAMPLE")
	else 
		%fullsample  =  @pagerange 
   	endif 

	'--- Option 2:  What % of the sample (%fullsample) should we use to test? ---'
	if @equaloption("H")<>"" then 
   		!holdout = @val(@equaloption("H")) 'maximum % of the training range to forecast over 
	else 
		!holdout = 0.1	 
	endif 
	
	'--- Option 3: What error measure(s) do you want? ---'
	if @equaloption("ERR")<>"" then 
		%err_measures = @equaloption("ERR")   
	else  
		%err_measures = "MSE" 
	endif 
	
	'--- Option 4: Do you want to see the raw matrices of forecasts and errors? ---'
	if @equaloption("KEEP_MATS")<>"" then
		!keep_matrices = @upper(@equaloption("KEEP_MATS"))="T"
	else
		!keep_matrices = 0
	endif
	
	'--- Option 5: Do you want to get error stats for dependent variable WITH transformations? ---'
	'NOTE: Only implemented for equation objects
	if @equaloption("VAR_FORM")<>"" then
		%var_form = @upper(@equaloption("VAR_FORM"))
	else
		%var_form = "BASE" 'default: base form (transformations stripped)
	endif

	'--- Call different programs based on type of object ---'
	%type = @getthistype
	while 1
		
		'--- Case 1. Equation object ---'
		if %type = "EQUATION" then
			exec ".\tscval_eq.prg"(sample = {%fullsample}, H = {!holdout}, ERR = {%err_measures}, KEEP_MATS = {!keep_matrices}, VAR_FORM = {%var_form}, PROC)
			exitloop
		endif
		
		'--- Case 2. VAR object ---'
		if %type = "VAR" then
			exec ".\tscval_var.prg"(sample = {%fullsample}, H = {!holdout}, ERR = {%err_measures}, KEEP_MATS = {!keep_matrices}, PROC)
			exitloop
		endif
		
		'--- Case 3. Other type of object ---'
		seterr "This add-in must be run from an equation or VAR object."
	wend


