'Motivation: Perform rolling time-series cross validation of an equation

'Description: 
' 	Program which takes an equation, rolls the sample, keeps producing forecasts,
' 	then stacks up vectors by horizon and computes errors at different horizons and for different error types
' 	Returns a few objects in the wf:
'		1. T_CV_{%err} --> a table with the eq name and error (see below) by forecast horizon | e.g. t_acc_mape
'		2. V_{%err} --> a vector for the given equation, where element 1 is 1-step-ahead, elem 2 is 2-step, etc. | e.g. "v_mape"

'##############################################################################
setmaxerrs 1
mode quiet

'--- Set the log mode ---'		
!debug = 1 'set to 1 if you want the logmsgs to display
if !debug = 0 then
	logmode +addin
else
	logmode logmsg
endif

'--- Check that we are on a time series page ---'
if @pagefreq = "u" or @ispanel then
	seterr "Procedure must be run on a time-series page."
endif

'--- Check the version ---'
if @vernum < 9 then
	seterr "EViews version 9.0 or higher is required to run this add-in."
endif

'--- Environment Info ---'
%freq = @pagefreq 'page frequency
%pagesmpl = @pagesmpl
%original_page = @pagename
%pagerange = @pagerange
%wf = @wfname
%eq = _this.@name 'get the name of whatever object we're using this on
%command = _this.@command 'command to re-estimate (with all the same options)
%method = _this.@method 

'--- Get Arguments (GUI or programmatic) ---'

'Was this run from the GUI?
!dogui=0
if not @hasoption("PROC") then
	!dogui=1 'if this is 1, we are running through the GUI
endif

'If the add-in is invoked through GUI, !result below will be changed to something else
!result=0

'Set up the GUI
if !dogui = 1 then
	%error_types = " ""MSE"" ""MAE"" ""RMSE"" ""MSFE"" ""medAE"" ""medSE"" ""MAPE"" ""SMAPE"" ""MPE"" ""MSPE"" ""RMSPE"" ""medPE"" ""medSPE"" ""Correct sign (count)"" ""Correct sign (%)"" " 			
	
	'Initialize with reasonable values
	%holdout = "0.10" 'default to testing over 10% of the training range
	%fullsample = %pagerange '%training_range
	%err_measures = "MAE"
	!keep_matrices = 0
			
	!result = @uidialog("edit", %fullsample, "Sample", "edit", %holdout, "Maximum % of the training range to hold out", _
		"list", %err_measures, "Preferred error measure", %error_types, "Check", !keep_matrices, "Keep matrices of forecasts and errors")	
	
	'--- Stop the program if the users Xs out of the GUI ---'
	if !result = -1 then 'will stop the program unless OK is selected in GUI
		stop
	endif
	
	'Map human-readable values to params
	if %err_measures = "Correct sign (count)" then
		%err_measures = "SIGN"
	endif
	if %err_measures = "Correct sign (%)" then
		%err_measures = "SIGNP"
	endif		
	!holdout = @val(%holdout)	
endif

'--- Grab program options if not running from the GUI ---'
if !dogui =0 then 'extract options passed through the program or use defaults if nothing is passed
	%fullsample  = @equaloption("SAMPLE") 
	!holdout = @val(@equaloption("H"))
	%err_measures = @equaloption("ERR")
	!keep_matrices = @val(@equaloption("KEEP_MATS"))
endif

'--- Get some information from the equation object ---'
wfselect %wf\{%original_page}
%group = @getnextname("g_")
_this.makeregs {%group}
%vars = @wunique({%group}.@depends)
%depvar = @word({%group}.@depends,1) 'dependent variable without transformations

'--- Adjust the training range (%fullsample) if necessary ---'

'Figure out the bounds of the estimable sample (assumes continuous series)
%mat = @getnextname("m_")
smpl @all
	stomna({%group}, {%mat}) 'the matrix will help find earliest and latest data to figure out appropriate data sample
smpl @all
%earliest = @otod(@max(@cifirst({%mat})))
%latest = @otod(@min(@cilast({%mat})))

'If the user set %fullsample to a range wider than what is actually estimable, shrink %fullsample to what is possible
if @dtoo(%earliest) > @dtoo(@word(%fullsample,1)) then
	%fullsample = @replace(%fullsample, @word(%fullsample,1), %earliest)
endif
 
if @dtoo(%latest) < @dtoo(@word(%fullsample,2)) then
	%fullsample = @replace(%fullsample, @word(%fullsample,2), %latest)
endif

'Clean up the intermediate stuff from this calculation
delete {%mat} {%group}

'--- Create a temporary page and copy relevant stuff to it ---'

'Create the page
!i=1
while @pageexist(%original_page+@str(!i))
	!i=!i+1
wend
%newpage = %original_page+@str(!i)
pagecreate(page={%newpage}) {%freq} {%pagerange}

'Copy stuff to it
wfselect %wf\{%original_page}
%group = @getnextname("g_")

'at this stage...may need to recalculate %vars if stepwise
if @upper(%method) = "STEPLS" then
	%search_vars = @trim(@right(%command,@len(%command)-@instr(%command," @ ")-2)) 'grab search regressors from the command
	%g = @getnextname("g_")
	group {%g} {%search_vars}
	%vars = @trim(%vars) + " " + @trim(@wunique({%g}.@depends))
	%vars = @wunique(%vars)
	delete {%g}
endif
group {%group} {%vars}
copy(g=d) {%original_page}\{%group} {%newpage}\

'If the equation object was unnamed, call it "untitled" on the new page
%eq = _this.@name
if %eq = "" then
	%eq = @getnextname("untitled_eq")
endif
copy {%original_page}\_this {%newpage}\{%eq} 'use _this in case we have untitled object

'--- Clean up behind ourselves on the original page, move on to the new one ---'
wfselect %wf\{%original_page}
smpl %pagesmpl
delete {%group}
wfselect %wf\{%newpage}

'--- Figure out where to begin estimation ---'
!obs = @round((@dtoo(@word(%fullsample,2))-@dtoo(@word(%fullsample,1)))*(1-!holdout)) 'how many observations in the first estimation sample?
%start_first_est = @word(%fullsample,1) 'start of first estimation sample
%end_first_est = @otod(@dtoo(%start_first_est)+!obs) 'end of first estimation sample
%first_fcst_start = @otod(@dtoo(%end_first_est)+1) 'start of the very first forecast we prepare
%fcst_end = @word(%fullsample,2)
!toteqs =  @dtoo(%fcst_end)-@dtoo(%end_first_est) 'how many equations will be estimated?

'--- Rolling estimates and forecasts ---'

'create (empty) group objects to store the error series
for %type lev pc sgn sym
	group g_{%type}
next

'At this point...if we are storing the matrices, create a group for the forecasts
if !keep_matrices then
	!num = 1
	
	while 1
		%matrix_page = "matpg_" + @str(!num)
		if @pageexist(%matrix_page)=0 then
			pagecreate(page={%matrix_page}) {%freq} {%pagerange}
			exitloop
		else
			!num = !num + 1
		endif
	wend
	
	wfselect %wf\{%newpage}
	group g_fcst
endif

'initialize
%start_est = @word(%fullsample,1)
%end_fcst = @word(%fullsample,2)
%fcst_list = "" 'list of forecast series, to be deleted at the end
for !i = 0 to (!toteqs-1)
	
	'Date strings
	%end_est = @otod(@dtoo(%end_first_est) + !i)
	%start_fcst = @otod(@dtoo(%end_est)+1)
	
	'Estimate over this sample
	smpl {%start_est} {%end_est}
		{%eq}.{%command}
		
	'Forecast
	smpl {%start_fcst} {%end_fcst}
		%fcst = @getnextname("fcst")
		{%eq}.forecast(f=na) {%fcst} '(f=na) --> NAs over history...series are forecast-only
		
	'calculate series of errors and add them to the correct group object
	smpl @all
	
		'--- 1. Level Errors ---'
		%f = @getnextname(%fcst+"_lev")									
		series {%f} = {%depvar} - {%fcst}
		g_lev.add {%f}
		
		'--- 2. Percentage Errors ---'
		%f = @getnextname(%fcst+"_pc")
		series {%f} = 100*({%depvar}-{%fcst})/{%depvar}
		g_pc.add {%f}
		
		'--- 3. Sign errors ---'
		'intuition--> "Did we correctly predict the direction of change between n periods ago and today?"
		
		!last_hist_point = @elem({%depvar}, %end_est) 'grab the last value from history
		series changes = {%depvar} - !last_hist_point
			changes = @recode(changes=0, 1e-08, changes) 'recode 0s to small positives (treat 0 as positive)
		
		%f = @getnextname(%fcst+"_sgn")
		series {%f} = (({%fcst}-!last_hist_point)/changes) > 0 '1 if correct sign, 0 other wise
		g_sgn.add {%f}	
		
		'--- 4. Sums for SMAPE (see http://robjhyndman.com/hyndsight/smape/) ---'
		%f = @getnextname(%fcst+"_sym")
		series {%f} = 2*@abs({%depvar} - {%fcst})/(@abs({%depvar}) + @abs({%fcst}))
		g_sym.add {%f}
		
	smpl @all
	
	'Add the forecast to its group if we're keeping the matrices
	if !keep_matrices then
		g_fcst.add {%fcst}
	endif
	
	'clean up
	%fcst_list = %fcst_list + " " + %fcst
	delete changes
		
next

'--- Grab the forecast matrix (if we're keeping it) ---'
if !keep_matrices then
	smpl @all
	stomna(g_fcst, m_fcst)
	copy {%newpage}\m_fcst {%matrix_page}\m_fcst
	delete g_fcst
endif
delete {%fcst_list}

'--- Create vectors with the n-step-ahead errors ---'
for %type lev pc sgn sym
	
	'Convert group of errors to matrix
	smpl {%first_fcst_start} {%fcst_end}
		stomna(g_{%type},m_{%type})
		
	'If we are keeping matrices, move this over
	if !keep_matrices then
		%tmp_mat = @getnextname(%tmp_mat)
		smpl @all
			stomna(g_{%type}, {%tmp_mat})
		copy {%newpage}\{%tmp_mat} {%matrix_page}\m_{%type}
		wfselect %wf\{%newpage}
		delete {%tmp_mat}
	endif
	smpl {%first_fcst_start} {%fcst_end}
		
	'Grab n-step-ahead error vectors from the matrix
	!horizon = 1
	while 1
		if @rows(m_{%type}) > 1 then
			'grab the forecast
			vector v_{%type}_{!horizon} = m_{%type}.@diag
			
			'the matrix is lower triangular...remove row 1 and the last column
			!cols = @columns(m_{%type})
			m_{%type} = m_{%type}.@dropcol(!cols)
			m_{%type} = m_{%type}.@droprow(1)
			
			'increment the horizon
			!horizon = !horizon + 1
		else
			'grab the last (longest) forecast
			vector v_{%type}_{!horizon} = m_{%type}.@diag
			delete m_{%type}
			exitloop 'we're done here
		endif
	wend
next

'--- Create the table & vector objects with output ---'
for %err {%err_measures} '1 table per error measure

	%table = "T_CV_" + %err
	table {%table}
	
	{%table}(1,1) = "SERIES"
	{%table}(2,1) = %depvar
	{%table}(3,1) = %depvar
	{%table}(1,2) = "Estimation_Object"
	{%table}(2,2) = %eq
	{%table}(3,2) = %eq
	{%table}(1,3) = "STEPS AHEAD ==>"
	{%table}(2,3) = "FORECASTS:"
	{%table}(3,3) = %err + ":"
	
	vector(!toteqs) v_cv_{%err} 'vector object mirroring the table (for convenience)
	
	'fill in the table with error measures
	!indent = 3 'two columns of metadata in column 1 (equation name, row labels)
	for !col=1 to !toteqs
		%head = @str(!col)
		{%table}(1, !col+!indent) = %head
		
		%horizon = @str(!col)
		'Absolute Errors
		!MAE  = @mean(@abs(v_lev_{%horizon}))
		!MSE = @mean(@epow(v_lev_{%horizon},2))
		!MSFE = !MSE 'some people use different terms
		!RMSE = @sqrt(!MSE)
		!medAE = @median(@abs(v_lev_{%horizon}))
		!medSE = @median(@epow(v_lev_{%horizon},2))
		
		'Percentage Errors
		!MAPE = @mean(@abs(v_pc_{%horizon}))
		!MPE = @mean(v_pc_{%horizon})
		!MSPE = @mean(@epow(v_pc_{%horizon},2))
		!RMSPE = @sqrt(!MSPE)
		!medPE = @median(@abs(v_pc_{%horizon}))
		!medSPE = @median(@epow(v_pc_{%horizon},2))
		!SMAPE = @mean(v_sym_{%horizon})
		
		'Sign errors
		!SIGN = @sum(v_sgn_{%horizon})
		!SIGNP = 100*(!SIGN/@obs(v_sgn_{%horizon}))
		
		'How many forecasts did we have at this horizon?
		!obs = @obs(v_lev_{%horizon})
		{%table}(2, !col+!indent) = @str(!obs)
		
		'STEP 5: Creaing a Single Vector of Errors
		'How good was the forecast at this horizon?
		v_cv_{%err}(!col) = !{%err}	
		{%table}(3, !col+!indent) = !{%err}
	next
	
	'Format the table
	!rows = @rows({%table})
	!cols = @columns({%table})
	{%table}.setformat(R2C4:R{!rows}C{!cols}) f.3 'only display three decimal places
	{%table}.setlines(R1C1:R1C{!cols}) +b 'underline the header row
	{%table}.setwidth(2) 16.8 'resize column 2 to fit text
	{%table}.setwidth(3) 15.1 'resize column 1 to fit text
	
	'tag these objects with the equation name
	for %object {%table} v_cv_{%err}
		{%object}.setattr(Estimation_Object) {%eq}
	next
	v_cv_{%err}.setattr(Series) {%depvar} 'series the errors pertain to
	
	'Copy over to the main page, make sure we don't overwrite existing objects
	wfselect %wf\{%original_page}
	if @isobject(%table) then
		%resulttable = @getnextname(%table)
	else
		%resulttable = %table
	endif	
	
	if @isobject("v_cv_"+%err) then
		%errorvector = @getnextname("v_cv_"+%err)
	else
		%errorvector = 	"v_cv_"+%err
	endif	
	
	copy {%newpage}\{%table} {%original_page}\{%resulttable}
	copy {%newpage}\v_cv_{%err} {%original_page}\{%errorvector}
	
	'be sure to select back to the temporary page
	wfselect %wf\{%newpage}
	 
next 'done looping over error measures

'--- If we're keeping the matrices around, go get them now ---'
if !keep_matrices then
	
	wfselect %wf\{%matrix_page}
	
	'Assign metadata
	m_sgn.setattr(Description) Matrix of "correct-sign" errors. (1=correct direction of change)
	m_lev.setattr(Description) Matrix of errors in the same units as the dependent variable.
	m_pc.setattr(Description)  Matrix of percentage errors.
	m_sym.setattr(Description) Matrix of symmetric errors used in SMAPE calculation.
	m_fcst.setattr(Description) Matrix of forecasts from tscval. Note that this matrix contains only forecast (no actuals).
	
	%mats = @wlookup("m_*", "matrix")
	for %mat {%mats}
		wfselect %wf\{%matrix_page}
		
		'Assign some metadata
		{%mat}.setattr(Interpretation) Number of rows = workfile range. Each column = forecast from model trained over one training sample.
		{%mat}.setattr(Series) {%depvar}
		{%mat}.setattr(Estimation_Object) {%eq}
		
		'Set row labels (this is tedious)
		!obs = @obsrange
		%sv = @getnextname("sv_tmp")
		svector(!obs) {%sv}
		for !i = 1 to !obs
			{%sv}(!i) = @otod(!i)
		next
		%labels = @wjoin({%sv})
		{%mat}.setrowlabels {%labels}
		delete {%sv}
		
		'Copy back to the original page
		wfselect %wf\{%original_page}
		if @isobject(%mat)=0 then
			copy {%matrix_page}\{%mat} {%original_page}\{%mat}
		else
			%obj = @getnextname(%mat)
			copy {%matrix_page}\{%mat} {%original_page}\{%obj}
		endif
	next
	
	pagedelete {%matrix_page}
endif

'--- Delete the temporary page ---'
pagedelete {%newpage}
wfselect %wf\{%original_page}

'--- Show the table if we ran from the GUI ---'
if !dogui=1 then
	show {%resulttable}
endif

'##################################################################################


