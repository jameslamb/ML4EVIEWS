'Author: James Lamb, Abbott Laboratories

'Motivation: Given a page frequency, return a string object with
'the date format string.

'##################################################################
'##################################################################
'##################################################################	
	
	'small program for accomplishing the annoying task of getting
	'the correct date format for EViews date functions.

	%freq = @pagefreq
	
	'---- Date format ----'
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
	
'##################################################################
'##################################################################
'##################################################################
