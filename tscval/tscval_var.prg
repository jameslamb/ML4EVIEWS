setmaxerrs 1
mode quiet
logmode logmsg
		
!debug = 1 'set to 1 if you want the logmsgs to display

if !debug = 0 then
	logmode +addin
else
	logmsg 'pop up the log
endif

logmsg Running PROC on VAR

'STEP 1: Figure out if the add-in is run through GUI or programmatically
!dogui=0

logmsg Looking for Program Options
if not @hasoption("PROC") then
	'this is run through GUI
	logmsg This is run through GUI
	!dogui=1
endif

'--- Environment Info ---'
logmsg Getting Environment Info
%freq = @pagefreq 'page frequency
%pagesmpl = @pagesmpl
%pagename = @pagename
%pagerange = @pagerange
%wf = @wfname
%var = _this.@name 'get the name of whatever object we're using this on
%command = {%var}.@command 'command to re-estimate (with all the same options) 

'If the add-in is invoked through GUI, !result below will be changed to something else
!result=0
'Set up the GUI
if !dogui = 1 then
	!keep_fcst = 0
	%error_types = " ""MSE"" ""MAE"" ""RMSE"" ""MSFE"" ""medAE"" ""MAPE"" ""SMAPE"" ""MPE"" ""MSPE"" ""RMSPE"" ""medPE"" ""Correct sign (count)"" ""Correct sign (%)"" " 			
	'Initialize with reasonable values
	%holdout = "0.10" 'default to testing over 10% of the training range
	%fullsample = %pagerange '%training_range
	%err_measures = "MAE"
	!keep_fcst = 0
			
	!result = @uidialog("edit", %fullsample, "Sample", "edit", %holdout, "Maximum % of the training range to hold out", _
		"list", %err_measures, "Preferred error measure", %error_types, "Check", !keep_fcst, "Keep the forecast series objects?" )	
	'Map human-readable values to params
	if %err_measures = "Correct sign (count)" then
		%err_measures = "SIGN"
	endif
	if %err_measures = "Correct sign (%)" then
		%err_measures = "SIGNP"
	endif		
	!holdout = @val(%holdout)	
endif

'choose dialog outcomes
if !result = -1 then 'will stop the program unless OK is selected in GUI
	logmsg CANCELLED
	STOP
endif

if !dogui =0 then 'extract options passed through the program or use defaults if nothing is passed
	%fullsample  = @equaloption("SAMPLE") 
	!holdout = @val(@equaloption("H"))
	%err_measures = @equaloption("ERR") 
	!keep_fcst = @val(@equaloption("K"))
endif

'Create new page for subsequent work
!counter=1
while @pageexist(%pagename+@str(!counter))
	!counter=!counter+1
wend

%newpage = %pagename+@str(!counter)

pagecreate(page={%newpage}) {%freq} {%pagesmpl}

'copy relevant information
wfselect {%wf}\{%pagename}

'Grab a bit of information from the equation
%reggroup = @getnextname("g_")
%regmat = @getnextname("mat_")
%varmodel = @getnextname("m_model_")

'Extract Endogeneous and Exogeneous Variable from the VAR
{%var}.makemodel({%varmodel})

%endoglist = {%varmodel}.@endoglist  'list of endogeneous variable in VAR

group {%reggroup}
%reglist = {%varmodel}.@exoglist + {%varmodel}.@endoglist
for %each {%reglist}
	{%reggroup}.append {%each}
next
delete {%varmodel}

''Re-work the training range if needed
smpl @all
stomna({%reggroup}, {%regmat}) 'the matrix will help find earliers and latest data to figure out appropriate data sample

'Figure out the bounds of the data that can be estimated over
%earliest = @otod(@max(@cifirst({%regmat})))
%latest = @otod(@min(@cilast({%regmat})))

'If training range interval is wider than available range interval, replace declared training range with available data range
if @dtoo(%earliest) > @dtoo(@word(%fullsample,1)) then
	%fullsample = @replace(%fullsample, @word(%fullsample,1), %earliest)
endif
 
if @dtoo(%latest) < @dtoo(@word(%fullsample,2)) then
	%fullsample = @replace(%fullsample, @word(%fullsample,2), %latest)
endif

''reset the sample back to what it was	
smpl %pagesmpl

''copy all base series that are needed to the new page
copy(g=d) {%pagename}\{%reggroup} {%newpage}\
copy {%pagename}\{%var} {%newpage}\
delete %reggroup

''move to the new page
wfselect {%wf}\{%newpage}

'*************CREATING VAR DUPLICATE AND SERIES DUPLICATES************
'We will create error vectors for each endogenous variable, so need to make sure name length limit is never exceeded. I will recode names of all endog variables and re-estimate VAR
!index = 1
%endogrenamelist = ""
for %each {%endoglist}
	%index = @str(!index)
	copy {%each} edg_{%index}
	%endogrenamelist = %endogrenamelist + "EDG_" + %index + " "
	!index=!index+1
next

%endogwinterleave = @winterleave(%endoglist, %endogrenamelist)
for %old %new {%endogwinterleave}
	%command = @replace(%command,%old, %new)
next
smpl @all
var var_new.{%command}

'Create NEW VAR with renamed variables - we will be using duplicate VAR for the rest of the code

''STEP 1: Cut Sample into Training and Testing Ranges
'count # of obs in the training set
logmsg STEP 1: Checking/Modifying Samples - Cut Sample into Training and Testing Ranges
!trainobscount  = @round((@dtoo(@word(%fullsample,2))-@dtoo(@word(%fullsample,1)))*(1-!holdout))
%shorttrainend = @otod(!trainobscount+@dtoo(%earliest)) 'this is the end of the training sample
%longfcststart = @otod(@dtoo(%shorttrainend)+1)'where longest forecast begins
!toteqs = @dtoo(@word(%fullsample,2))-@dtoo(%shorttrainend) 'total numbers of estimations

'STEP 2: Running Estimates
logmsg STEP 2: Running Estimates
'Name Lists that Need to Be Populated

%forecasts = "" 'list of forecasts

%vectornamelists = "v_err v_err_pc v_err_sgn v_err_sym" 'list of vector namelists

	for %variable {%endogrenamelist}	
		%v_err_{%variable} = "" 'traditional level errors (yhat-y)
		%v_err_pc_{%variable} = "" 'percentage errors
		%v_err_sgn_{%variable} = "" 'sign errors (direction of change
		%v_err_sym_{%variable} = "" 'scaled symmetric errors for sMAPE
	next	
		
%forecastseries = ""
!index=1
for !i = 0 to !toteqs-1	
	'Date Strings
	%trainend = @otod(@dtoo(%shorttrainend)+!i) 'end of the training sample (incremented by 1 in each loop step)
	%trainstart = @word(%fullsample,1) 'beginning of the training sample
	%fcststart = @otod(@dtoo(%trainend)+1) 'forecasting begins after training sample ends
	%fcstend = @word(%fullsample,2) 'end of the forecast
	
	'Estimate the model over this sample
	smpl %trainstart %trainend
	var_new.{%command} 're-estimate the equation
	'{%var}.{%command} 're-estimate the equation
	
	'Forecast the model over this sample
	smpl %fcststart %fcstend
	%index = @str(!index)
	var_new.forecast(f=actual) {%index}
	{%var}.forecast(f=actual) {%index} 'create forecasts: limit on index is 3 characters. While it is unlikely that there will be a longer sample - need to make this robust

	for %variable {%endogrenamelist}
		'******Calculate Errors
		'ERROR 1: Absolute Errors
		smpl @all
		series ERR_{%variable}_{%index} = {%variable} - {%variable}_{%index}
		if @isobject("smpl") then
			delete smpl
		endif
		sample smpl %longfcststart %fcstend
		vector V_ERR_{%variable}_{%index} = @convert(ERR_{%variable}_{%index},smpl) 'convert to vector
		%v_err_{%variable} = %v_err_{%variable}+"V_ERR_"+%variable+"_"+%index+" " 'populate vector namelist
	
		'ERROR 2: Percentage Errors
		smpl @all
		series ERR_PC_{%variable}_{%index} = (({%variable} - {%variable}_{%index})/{%variable})*100
		if @isobject("smpl") then
			delete smpl
		endif	
		sample smpl %longfcststart %fcstend	
		vector V_ERR_PC_{%variable}_{%index} = @convert(ERR_PC_{%variable}_{%index}, smpl)
		%v_err_pc_{%variable} = %v_err_pc_{%variable} + "V_ERR_PC_"+%variable+"_"+%index+" " 'populate vector namelist
		
		'ERROR 3: Sign Erors (should be over the horizon. So 2 step ahead asks: "Did we correctly predict the direction of change between two periods ago and today?")
		smpl @all
		!last_hist_point = @elem({%variable}, %trainend) 'grab the last value from history
		
		'get a series of actual changesi n the history
		series changes = {%variable} - @elem({%variable}, %trainend)
		changes = @recode(changes=0, 1e-08, changes) 'recode 0s to small positives (treat 0 as positive)
		
		'if change in fcst and change in actual are in the same direciton, the sign was correct
		series ERR_SGN_{%variable}_{%index} = (({%variable}_{%index} -  !last_hist_point) / changes) > 0 '1 if correct sign, 0 otherwise
		if @isobject("smpl") then
			delete smpl
		endif	
		sample smpl %longfcststart %fcstend	
		vector V_ERR_SGN_{%variable}_{%index} = @convert(ERR_SGN_{%variable}_{%index}, smpl)
		%v_err_sgn_{%variable} = %v_err_sgn_{%variable} + "V_ERR_SGN_" + %variable+"_"+%index + " " 'populate sign vector namelist
		
		'ERROR 4: Sums for sMAPE (see http://robjhyndman.com/hyndsight/smape/)
		smpl @all
		series ERR_SYM_{%variable}_{%index} = 2*@abs({%variable} - {%variable}_{%index})/(@abs({%variable}) + @abs({%variable}_{%index}))
		if @isobject("smpl") then
			delete smpl
		endif	
		sample smpl %longfcststart %fcstend	
		vector V_ERR_SYM_{%variable}_{%index} = @convert(ERR_SYM_{%variable}_{%index}, smpl)
		%v_err_sym_{%variable} = %v_err_sym_{%variable} + "V_ERR_SYM_" + %variable+"_"+%index + " " 'populate symmetric error vector namelist
			'*****		
	%forecasts = %forecasts + %variable+"_"+%index+" " 'creating a list of all series that are forecasted		
	next	
	!index=!index+1 'this is the index for each forecast series
next	
	
'STEP 3: Create Vectors with N-Step Ahead Error
logmsg STEP 3: Create Vectors with N-Step Ahead Error

for %list {%vectornamelists}
	for %variable {%endogrenamelist}
		if @isobject("m_matrix") then
			delete m_matrix
		endif
		
		matrix(!toteqs, !toteqs) m_matrix
		
		'Create Vectors with N-Step Ahead Error		
		
		'Assemble the vectors in a matrix
		for %each {%{%list}_{%variable}}
			!count = @wfind(%{%list}_{%variable}, %each)
			colplace(m_matrix, {%each}, !count)
		next	
		
		'Go through and grab each vector (1-period ahead is on the main diagonal of the full matrix)
		!horizon = 1
		while 1
			if @rows(m_matrix) > 1 then
				'grab the forecast
				vector e_{%list}_{%variable}_{!horizon} = m_matrix.@diag
				
				'the matrix is upper traingular...remove row 1 and the last column
				!cols = @columns(m_matrix)
				m_matrix = m_matrix.@dropcol(!cols)
				m_matrix = m_matrix.@droprow(1)
				
				'increment the horizon
				!horizon = !horizon + 1
			else
				'grab the last (longest) forecast
				vector e_{%list}_{%variable}_{!horizon} = m_matrix.@diag			
				exitloop 'we're done here
			endif
		wend	
	next
next	

'STEP 4: Creating the Forecast Evaluation Table
logmsg STEP4: Creating the Forecast Evaluation Table(s)
%tables = ""
for %old %new {%endogwinterleave}
	for %err {%err_measures} '1 table per error measure
		
		%table = "T_"+%old+"_"+ %err
		table {%table}
		
		{%table}(1,3) = "STEPS AHEAD ==>"
		{%table}(2,1) = "EQUATION"
		{%table}(3,1) = %eq
		{%table}(3,2) = "FORECASTS:"
		{%table}(4,1) = %eq
		{%table}(4,2) = %err + ":"
		
		!indent = 2 'two columns of metadata in column 1 (equation name, row labels)
		vector(!toteqs) V_{%new}_{%err}
		
		'fill in the table with error measures
		for !col=1 to !toteqs
			%head = @str(!col)
			{%table}(2, !col+!indent) = %head
			
			%horizon = @str(!col)
			'Absolute Errors
			!MAE  = @mean(@abs(e_v_err_{%new}_{%horizon}))
			!MSE = @mean(@epow(e_v_err_{%new}_{%horizon},2))
			!MSFE = !MSE 'some people use different terms
			!RMSE = @sqrt(!MSE)
			!medAE = @median(@abs(e_v_err_{%new}_{%horizon}))
			
			'Percentage Errors
			!MAPE = @mean(@abs(e_v_err_pc_{%new}_{%horizon}))
			!MPE = @mean(e_v_err_pc_{%new}_{%horizon})
			!MSPE = @mean(@epow(e_v_err_pc_{%new}_{%horizon},2))
			!RMSPE = @sqrt(!MSPE)
			!SMAPE = @mean(e_v_err_sym_{%new}_{%horizon})
			!medPE = @med(@abs(e_v_err_pc_{%new}_{%horizon}))
			
			'Sign errors
			!SIGN = @sum(e_v_err_sgn_{%new}_{%horizon})
			!SIGNP = 100*(!SIGN/@obs(e_v_err_sgn_{%new}_{%horizon}))
			
			'How many forecasts did we have at this horizon?
			!obs = @obs(e_v_err_{%new}_{%horizon})
			{%table}(3, !col+!indent) = @str(!obs)
		
			'STEP 5: Creaing a Single Vector of Errors
			'logmsg STEP 5: Creating a Single Vector of Errors
			'How good was the forecast at this horizon?
			v_{%new}_{%err}(!col) = !{%err}	
			{%table}(4, !col+!indent) = !{%err}			
		next	
		
		!cols = @columns({%table})
		{%table}.setformat(R3C3:R4C{!cols}) f.3 'only display three decimal places
		{%table}.setlines(R2C1:R2C{!cols}) +b 'underline the header row
		
		'tag these objects with the equation name
		for %object {%table} v_{%new}_{%err}
			{%object}.setattr(Source_Equation) {%var}
		next
		
	'Copy over to the main page, make sure we don't overwrite existing objects
	wfselect {%wf}\{%pagename}
	
	if @isobject(%table) then
		%resulttable = @getnextname(%table)	
	else
		%resulttable = %table	
	endif
	
	%tables = %tables+%resulttable+" "
	
	if @isobject("v_"+%err+"_"+%old)then
		%errorvector = @getnextname("v_"+%err+"_"+%old+"_")
		else
		%errorvector = 	"v_"+%err+"_"+%old
	endif
	
	wfselect {%wf}\{%newpage}
	copy {%newpage}\{%table} {%pagename}\{%resulttable}
	copy {%newpage}\v_{%new}_{%err} {%pagename}\{%errorvector}
	next
next	

	if !keep_fcst = 1 then
		for %each {%forecasts}			
			wfselect {%wf}\{%pagename}
			if @isobject(%each) then
				%seriesname = @getnextname(%each+"_")
			else
				%seriesname = %each
			endif
			logmsg %seriesname 
			copy {%newpage}\{%each} {%pagename}\{%seriesname}			
		next
	endif
	wfselect {%wf}\{%newpage}

	pagedelete {%newpage}
	
'if this was run from the GUI (on one equation), show the table of results
wfselect {%wf}\{%pagename}
if !dogui=1 then
	for %each {%tables}
		show {%each}
	next
endif

'Program Complete
logmsg Program is Complete


