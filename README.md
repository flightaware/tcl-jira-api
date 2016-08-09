Tcl JIRA REST API Package
===========================

This package provides a Tcl native interface to the JIRA REST API as 
documented at https://docs.atlassian.com/jira/REST/cloud/

Requirements
------------

* A [JIRA](https://atlassian.com/JIRA) server or JIRA Cloud instance
* Tcl 8.5 or newer

Other Stuff that's Included
---------------------------

* jira-git-hook is a script which will do awesome things once it exists

In Brief
--------

The package can authenticate to the JIRA server using Basic auth (where the
encoded username and password are supplied with every call) or by
authenticating and receiving a cookie which is associated with a specific user
session. 


Example Code
------------


    #!/usr/bin/env tclsh

    package require jira

	::jira::config -server example.atlassian.net

	if {![::jira::loadcookies]} {
		::jira::config -username "username" -password "password"
		if {[::jira::login]} {
			::jira::savecookies
		}
	}

	::jira::config -debug 1

	puts "The project ID for the example project is [::jira::getItemID project Example]"

	::jira::getIssue "EX-1000" issue -getcomments 1
	parray issue

	::jira::addComment "EX-1000" result -body "Lorem ipsum dolor sit amet"
