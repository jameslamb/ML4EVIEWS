'Author: James Lamb, Abbott Labs

'Motivation: Estimate a few models of US industrial production.

'##########################################################################################################
'##########################################################################################################
'##########################################################################################################

	'NOTE: Assumes that you have the FRED database in your DB registry
	
	logmsg
	logmsg ------ BEGINNING EXAMPLE1 ------
	logmsg

		tic ' start timer
		
	'==== Global Variables ===
	%CVAL = @replace(@runpath, "DOCS\","") + "tscval.prg"
		
	logmsg --- Setting up wf full of equations
		
		'Create workfile
		wfcreate(wf=CV_EXAMPLE, page = DATA_M) m 1920 2020
		
		'Fetch data
		fetch(d=FRED) INDPRO CPIAUCSL
		
		'Estimate a few differerent models
		equation eq_01.ls d(indpro) c ar(1)
		equation eq_02.ls d(indpro) c ar(1) ar(2) ma(1)
		equation eq_03.ls indpro c @trend @trend^2
		
		'and a var	
		var var_1.ls 1 2 d(cpiaucsl) d(indpro)	

	logmsg --- Assessing Forecast errors

		%eqs = @wlookup("EQ_*", "equation") + " " + @wlookup("VAR_*", "var")
		for %eq {%eqs}
			
			%endhist = INDPRO.@last
			%longest_smpl = "1920 " + %endhist
			%dep = "INDPRO"
			'exec %CVAL %eq "2013M01" %longest_smpl  "MAPE" "FALSE"
			{%eq}.tscval(TRAIN = %longest_smpl, H=0.10, ERR="MSE", K=F, DEP=%dep)
			
			'build up the table of errors
			%main_tbl = "T_FCST_ACC"
			if @isobject(%main_tbl) = 0 then
				rename t_acc t_fcst_acc
			else
				'append those last two lines to the running forecast table
				!next = @rows(t_fcst_acc) + 1
				!cols = @columns(t_acc) 'the table return
				
				'check if we need to add columns to the main table
				if @columns({%main_tbl}) < @columns(t_acc) then
					!end_main = @columns({%main_tbl})
					!diff = @columns(t_acc) - @columns({%main_tbl})
					'add a few columns
					{%main_tbl}.insertcol(!end_main) !diff
				endif
				
				'copy the third and fourth rows of t_acc (w/ the errors) and append to the bottom of t_fcst_acc
				t_acc.copyrange 3 1 4 {!cols} t_fcst_acc {!next} 1 
				delete t_acc	
			endif
		next

		'Go through each column of the table, color in the cell w/ the lowest error
		for !col = 3 to @columns(t_fcst_acc)
			!best_err = 0
			!error_rows = ((@rows(t_fcst_acc))- 2)/2 'first two rows are headers, below alternates between count and error measure
			vector(!error_rows) v_tmp = NA
			for !row = 4 to @rows(t_fcst_acc) step 2
				!err = @val(t_fcst_acc(!row,!col))
				!vec_row = (!row - 2)/2
				v_tmp(!vec_row) = !err
			next
			!minrow = 2 + 2*@imin(v_tmp)
			t_fcst_acc.setfillcolor(R{!minrow}C{!col}:R{!minrow}C{!col}) blue
			t_fcst_acc.settextcolor(R{!minrow}C{!col}) white
			
		next
		delete v_tmp
		
		show t_fcst_acc
		
		%elapsed = @str(@toc)
		
	logmsg
	logmsg ------ EXAMPLE1 COMPLETE ({%elapsed}s) ------
	logmsg
'##########################################################################################################
'##########################################################################################################
'##########################################################################################################


