Tcl JIRA REST API Package
===========================

This package provides a Tcl native interface to the JIRA REST API as 
documented at https://docs.atlassian.com/jira/REST/cloud/

Requirements
------------

* A [JIRA](https://atlassian.com/JIRA) server or JIRA Cloud instance
* Tcl 8.5 or newer

In Brief
--------

The package can authenticate to the JIRA server using Basic auth (where the
encoded username and password are supplied with every call).


Example Code
------------


    #!/usr/bin/env tclsh

    package require jira

	::jira::config -server example.atlassian.net
	::jira::config -username "username" -password "password"

	::jira::config -debug 1

	puts "The project ID for the example project is [::jira::getItemID project Example]"

	::jira::getIssue "EX-1000" issue -getcomments 1
	parray issue

	::jira::addComment "EX-1000" result -body "Lorem ipsum dolor sit amet"
