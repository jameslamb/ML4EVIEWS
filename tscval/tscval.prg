'Author: James Lamb, Abbott Economics

'Motivation: Perform rolling time-series corss validation.

'Description: 
' 	Program which takes an equation, rolls the sample, keeps producing forecasts,
' 	then stacks up vectors by horizon and computes errors at different horizons.
' 	Returns a few objects in the wf:
'		1. T_ACC --> a table with the eq name and error (see below) by forecast horizon
'		2. V_{%eq}_{%ERR_MEASURE} --> a vector for the given equation, where element 1 is 1-step-ahead, elem 2 is 2-step, etc.

'##########################################################################################################
'##########################################################################################################
'##########################################################################################################
setmaxerrs 1
mode quiet
logmode logmsg
logmsg

'NOTE: Currently only supports equation objects (no VARs)
		
!debug = 1 'set to 1 if you want the logmsgs to display

if !debug = 0 then
	logmode +addin
endif
		
'check that an object exists
%type = @getthistype
if %type="NONE" then
	@uiprompt("No object found, please open an Equation or VAR object")
	stop
endif
		
'check that {%eq} object is an equation or VAR
if %type<>"EQUATION" then
	@uiprompt("Procedure can only be run from an Equation or VAR object")
	stop
endif

'STEP 1: Figure out if the add-in is run through GUI or programmatically
!dogui=0

logmsg Looking for Program Options
if not @hasoption("PROC") then
	'this is run through GUI
	logmsg This is rung through GUI
	!dogui=1
endif


'--- Environment Info ---'
logmsg Getting Environment Info
%freq = @pagefreq 'page frequency
%pagesmpl = @pagesmpl
%pagename = @pagename
%pagerange = @pagerange
%wf = @wfname
%eq = _this.@name 'get the name of whatever we're using this on
%command = {%eq}.@command 'command to re-estimate (with all the same options) 


''If the add-in is invoked through GUI
!result=0
'Set up the GUI
if !dogui = 1 then
	!keep = 0
	%error_types = " ""MSE"" ""MAE"" ""RMSE"" ""MSFE"" ""medAE"" ""MAPE"" ""SMAPE"" ""MPE"" ""MSPE"" ""RMSPE"" ""medPE"" ""Correct sign (count)"" ""Correct sign (%)"" " 			
	'Initialize with reasonable values
	%holdout = "0.10" 'default to testing over 10% of the training range
	%fullsample = %pagerange '%training_range
	%err_measure = "MAE"
	!keep = 0
			
	!result = @uidialog("edit", %fullsample, "Sample", "edit", %holdout, "Maximum % of the training range to hold out", _
		"list", %err_measure, "Preferred error measure", %error_types, "Check", !keep, "Keep the forecast series objects?" )	
	'Map human-readable values to params
	if %err_measure = "Correct sign (count)" then
		%err_measure = "SIGN"
	endif
	if %err_measure = "Correct sign (%)" then
		%err_measure = "SIGNP"
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
	%err_measure = @equaloption("ERR") 
	!keep = @val(@equaloption("K"))
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
{%eq}.makeregs {%reggroup}
%regvars = @wunique({%reggroup}.@depends)
%depvar = @word({%reggroup}.@depends,1) 'dependent variable without transformations

'Re-work the training range if needed
smpl @all
stomna({%reggroup}, {%regmat}) 'the matrix will help find earliers and latest data to figure out appropriate data sample

%earliest = @otod(@max(@cifirst({%regmat})))
%latest = @otod(@min(@cilast({%regmat})))

'If training range interval is wider than available range interval, replace declared training range with available data range
if @dtoo(%earliest) > @dtoo(@word(%fullsample,1)) then
	%fullsample = @replace(%fullsample, @word(%fullsample,1), %earliest)
endif
 
if @dtoo(%latest) < @dtoo(@word(%fullsample,2)) then
	%fullsample = @replace(%fullsample, @word(%fullsample,2), %latest)
endif
		
smpl %pagesmpl 'reset the sample back to what it was
delete {%regmat} {%reggroup}

%reggroup = @getnextname("g_")
group {%reggroup} {%regvars}
'copy all base series that are needed to the new page
copy(g=d) {%pagename}\{%reggroup} {%newpage}\
copy {%pagename}\{%eq} {%newpage}\
delete %reggroup

'move to the new page
wfselect {%wf}\{%newpage}

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
'-----------------------'

'STEP 1: Cut Sample into Training and Testing Ranges
'count # of obs in the training set
logmsg STEP 1: Checking/Modifying Samples - Cut Sample into Training and Testing Ranges
!trainobscount  = @round((@dtoo(@word(%fullsample,2))-@dtoo(@word(%fullsample,1)))*(1-!holdout))
!test = @dtoo(@word(%fullsample,2))-@dtoo(@word(%fullsample,1))
%shorttrainend = @otod(!trainobscount+@dtoo(%earliest)) 'this is the end of the training sample
%longfcststart = @otod(@dtoo(%shorttrainend)+1)'where longest forecast begins
!toteqs = @dtoo(@word(%fullsample,2))-@dtoo(%shorttrainend) 'total numbers of estimations

'STEP 2: Running Estimates
logmsg STEP 2: Running Estimates

'%forecasts = ""
'Vector Name Lists that Need to Be Populated

%v_err = ""
%v_err_pc = ""

%vectornamelists = "v_err v_err_pc" 'list of vector namelists

%forecastseries = ""
for !i = 0 to !toteqs-1
	'Date Strings
	%trainend = @otod(@dtoo(%shorttrainend)+!i) 'end of the training sample (incremented by 1 in each loop step)
	%trainstart = @word(%fullsample,1) 'beginning of the training sample
	%fcststart = @otod(@dtoo(%trainend)+1) 'forecasting begins after training sample ends
	%fcstend = @word(%fullsample,2) 'end of the forecast
	'Estimate the model over this sample
	smpl %trainstart %trainend
	{%eq}.{%command} 're-estimate the equation
	'Forecast the model over this sample
	smpl %fcststart %fcstend
	{%eq}.forecast(f=actual) {%depvar}_f_{%fcststart} 'create forecasts
	%forecastseries  = %forecastseries + %depvar+"_f_"+%fcststart+" " 'list of all forecasted series
	'*****Calculate Errors
		'ERROR 1: Absolute Errors
		smpl @all
		series ERR_{%fcststart} ={%depvar} - {%depvar}_f_{%fcststart}
		if @isobject("smpl") then
			delete smpl
		endif
		sample smpl %longfcststart %fcstend
		vector V_ERR_{%fcststart} = @convert(ERR_{%fcststart}, smpl) 'convert to vector
		%v_err = %v_err + "V_ERR_"+ %fcststart + " " 'populate vector namelist
		
		'ERROR 2: Percentage Errors
		smpl @all
		series ERR_PC_{%fcststart} = (({%depvar} - {%depvar}_f_{%fcststart})/{%depvar})*100
		if @isobject("smpl") then
			delete smpl
		endif	
		sample smpl %longfcststart %fcstend	
		vector V_ERR_PC_{%fcststart} = @convert(ERR_PC_{%fcststart}, smpl)
		%v_err_pc = %v_err_pc + "V_ERR_PC_"+%fcststart+" " 'populate vector namelist
		
		'ERROR 3: Sign Erors (should be over the horizon. So 2 step ahead asks: "Did we correctly predict the direction of change between two periods ago and today?")
		
		'LEAVE FOR LATER
	'*****		
	'%forecasts = %forecasts + %depvar+"_f_"+%fcststart+" " 'creating a list of all series that are forecasted
	smpl @all
next

'STEP 3: Create Vectors with N-Step Ahead Error
logmsg STEP 3: Create Vectors with N-Step Ahead Error

for %list {%vectornamelists}
	if @isobject("m_matrix") then
		delete m_matrix
	endif
	
	matrix(!toteqs, !toteqs) m_matrix
	!count=1
	
	if @isobject("dropvector") then
		delete dropvector
	endif
	
	vector(!toteqs) dropvector=0
	for !i=1 to !toteqs
		dropvector(!i) = !i
	next
	
	'Create Vectors with N-Step Ahead Error
	%e_{%list} = ""
	for %each {%{%list}}
		%count = @str(!count)
		colplace(m_matrix, {%each}, !count)
		if @rows(dropvector)>1 then	
			dropvector = dropvector.@droprow(1)
		vector e_{%list}_{%count} = m_matrix.@row(!count)
		e_{%list}_{%count} = e_{%list}_{%count}.@droprow(dropvector)
		else
		vector e_{%list}_{%count} = m_matrix.@row(!count)	
		endif
		%e_{%list} = %e_{%list} + "e_"+%list+"_"+%row+" "
		!count=!count+1
	next
next

'STEP 4: Creating the Forecast Evaluation Table
logmsg STEP4: Creating the Forecast Evaluation Table

table t_result

t_result(1,3) = "STEPS AHEAD ==>"
t_result(2,1) = "EQUATION"
t_result(3,1) = %eq
t_result(3,2) = "FORECASTS:"
t_result(4,2) = %err_measure+":"

!indent = t_result.@cols+1

vector(!toteqs) V_{%err_measure}

for !col=1 to !toteqs
	%head = @str(!col)
	t_result(2, !col+!indent) = %head
	
	%counter = @str(!col)
	'Absolute Errors
	!MAE  = @mean(@abs(e_v_err_{%counter}))
	!MSE = @mean(@epow(e_v_err_{%counter},2))
	!MSFE = !MSE
	!RMSE = @sqrt(!MSE)
	!medAE = @median(@abs(e_v_err_{%counter}))
	
	'Percentage Errors
	!MAPE = @mean(@abs(e_v_err_pc_{%counter}))
	!MPE = @mean(e_v_err_pc_{%counter})
	!MSPE = @mean(@epow(e_v_err_pc_{%counter},2))
	!RMSPE = @sqrt(!MSPE)
	!SMAPE = @mean(e_v_err_pc_{%counter})
	!medPE = @med(@abs(e_v_err_pc_{%counter}))
	
	v_{%err_measure}(!col) = !{%err_measure}	
	t_result(4, !col+!indent) = !{%err_measure}	
next

!cols = @columns(t_result)
t_result.setformat(R3C3:R4C{!cols}) f.3 'only display three decimal places
t_result.setlines(R2C1:R2C{!cols}) +b 'underline the header row
		
show t_result

'STEP 5: Creaing a Single Vector of Errors
logmsg Step 5: Creating a Single Vector of Errors

wfselect {%wf}\{%pagename}
%resulttablename = @getnextname("t_result_")
%errorvecotrname = @getnextname("v_"+%err_measure+"_")

copy {%newpage}\t_result {%pagename}\{%resulttablename}
copy {%newpage}\v_{%err_measure} {%pagename}\{%errorvecotrname}

if !keep = 1 then
	for %each {%forecastseries}
		%seriesname = @getnextname(%each+"_")
		copy {%newpage}\{%each} {%pagename}\{%seriesname}
	next
endif

pagedelete {%newpage}

'if this was run from the GUI (on one equation), show the table of results
wfselect {%wf}\{%pagename}
if !dogui=1 then
	show {%resulttablename}
endif

'Program Complete
logmsg Program is Complete


