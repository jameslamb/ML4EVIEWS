'Motivation: Given a vector of cross-validation results, score the errors


'###################################################################################
setmaxerrs 1
mode quiet

'--- Set the log mode ---'	
	
	!debug = 0 'set to 1 if you want the logmsgs to display
	if !debug = 0 then
		logmode +addin
	else
		logmode logmsg
	endif
	
'--- Environment ---'

	%cv_vec = _this.@name
	
'--- Arguments ---'
	
	'[1] attr --> attribute name to use when storing the score in the CV vector's metadata.
	%attr = "tscv_score"
	if @equaloption("attr") <> "" then
		%attr = @equaloption("attr")
	endif
	
	'[2] npers --> give user the option to score on the first n periods
	!npers = @rows({%cv_vec})
	if @equaloption("npers") <> "" then
		!npers = @val(@equaloption("npers"))
	endif
	
	'[3] score_vec --> vector of weight for use in scoring the output
	%score_vec = ""
	if @equaloption("score_vec") <> "" then
		%score_vec = @equaloption("score_vec")
		
		'handle weirdness in the score_vec passed in
		while 1
			
			'Case 1. object doesn't exist
			if @isobject(%score_vec)=0 then
				%err = "The scoring vector " + %score_vec + " does not exist!"
				seterr %err
			endif
			
			'Case 2. score_vec has more rows than the cross validation vector
			if @rows({%score_vec}) > !npers then
				%warning = "WARNING: " + %score_vec + "has more elements than " + %cv_vec + ". Calculate score with only the first " + @str(!npers) + "elements of " + %score_vec + "?"
				!result = @uiprompt(%warning, "YN")
				
				if !result = 1 then
					%v = @getnextname("v_scr_")
					vector {%v} = @subextract(%score_vec, 1,1,!npers,1)
					%score_vec = %v
				else
					return
				endif
			endif
			
			'Case 3. score_vec has less rows than the cross validation vector
			if @rows({%score_vec}) < !npers then
				%warning = "WARNING: " + %score_vec + "has less elements than " + %cv_vec + ". Calculate score on only the first " + @str(!npers) + "elements of " + %cv_vec + "?"
				!result = @uiprompt(%warning, "YN")
				
				'If yes, pad the scoring vector with zeros to make it the same length as the CV vector
				if !result = 1 then
					
					'create a vector with the zeros
					%zeroes = @getnextname("z")
					vector {%zeroes} = @ones(!npers-@rows({%score_vec}),1)*0
					
					'create a new scoring vector
					%v = @getnextname("v_scr_")
					vector {%v} = @vcat({%score_vec}, {%zeroes})
					%score_vec = %v
					
					'clean up
					delete {%zeroes}
				else
					return
				endif
			endif
			
			'we are good
			exitloop
		wend
	endif
	
'--- Do the calculation ---'

	'default case: equal weights
	if %score_vec = "" then
		%v = @getnextname("v_scr_")
		vector(!npers) {%v} = 1/!npers
		%score_vec = %v
	endif
	
	'(potentially) grab a sub-vector of the cross-validation results (in case user only cares about the first few observations)
	%cv_tmp = @getnextname("cv_tmp_")
	vector {%cv_tmp} = @subextract({%cv_vec},1,1,!npers,1)
	
	'calculate score
	!score = @inner({%score_vec}, {%cv_tmp})
	delete {%cv_tmp}
	
	'put the score in the metadata of the cv vector
	if {%cv_vec}.@attr(%attr) <> "" then
		%warning = "WARNING: " + %cv_vec + " already has metadata attribute " + %attr + ". Would you like to overwrite?"
		!result = @uiprompt(%warning, "YN")
		
		while {%cv_vec}.@attr(%attr) <> ""
			
			'Case 1. Exit --> leave the program
			if !result = -1 or !result = 0 then
				return
			endif
			
			'Case 2. Yes --> move on
			if !result = 1 then
				exitloop
			endif
			
			'Case 3. No --> get a net attribute name
			if !result = 2 then
				!x = @uiedit(%attr, "Metadata attribute to store CV score in: ")
				'don't exitloop...keep prompting until we find an attribute name that doesn't exist
			endif
		wend
	endif
	{%cv_vec}.setattr({%attr}) !score
	
'--- Clean up ---'

	delete {%v} 'guaranteed to be exactly one temporary vector with this name


