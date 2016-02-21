	

	'This runs first when tscval() is run progammatically. It supplies defaults for unspecified arguments.

	'Option 1 = The full range we train models over
	if @equaloption("SAMPLE")<>"" then 
		%fullsample  = @equaloption("SAMPLE") 'returns actual option value to the right of the equation
	else 
		%fullsample  =  @pagerange 
   	endif 
		
	'Option 2 =  what % of the sample should we use to test? 
	if @equaloption("H")<>"" then 
   		!holdout = @val(@equaloption("H")) 'maximum % of the training range to forecast over 
	else 
		!holdout = 0.1	 
	endif 
	
	%holdout = @str(!holdout)
	
	'Option 3 = What error measure do you prefer? 
	if @equaloption("ERR")<>"" then 
		%err_measure = @equaloption("ERR")   
		else  
		%err_measure = "MSE" 
	endif 

	'Option 4 = Do you want to keep the forecast series objects?
	!keep_fcst = 0 
	if @equaloption("K")<>"" then 
		%keep = @equaloption("K") 
		!keep_fcst = (@upper(%keep)="TRUE") or (@upper(@left(%keep,1))="T") 
	endif
	%keep_fcst = @str(!keep_fcst)
	
	'Call different programs based on type of object
	%type = @getthistype
	if %type = "EQUATION" then
		exec ".\tscval_eq.prg"(sample = {%fullsample}, H = {%holdout}, ERR = {%err_measure}, K = {%keep_fcst}, PROC)
	else
		if %type = "VAR" then
			exec ".\tscval_var.prg"(sample = {%fullsample}, H = {%holdout}, ERR = {%err_measure}, K = {%keep_fcst}, PROC)
		else
			seterr "This add-in must be run from an equation or VAR object."
			stop
		endif
	endif


