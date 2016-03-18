	'This runs first when tscval() is run progammatically. It supplies defaults for unspecified arguments.

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

	'--- Call different programs based on type of object ---'
	%type = @getthistype
	while 1
		
		'--- Case 1. Equation object ---'
		if %type = "EQUATION" then
			exec ".\tscval_eq.prg"(sample = {%fullsample}, H = {!holdout}, ERR = {%err_measures}, PROC)
			exitloop
		endif
		
		'--- Case 2. VAR object ---'
		if %type = "VAR" then
			exec ".\tscval_var.prg"(sample = {%fullsample}, H = {!holdout}, ERR = {%err_measure}, PROC)
			exitloop
		endif
		
		'--- Case 3. Other type of object ---'
		seterr "This add-in must be run from an equation or VAR object."
	wend


