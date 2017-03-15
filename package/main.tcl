package require http
package require tls
package require yajltcl
package require base64

::tls::init -ssl2 0 -ssl3 0 -tls1 1
::http::register https 443 ::tls::socket

namespace eval ::jira {
	variable config
	
	##############################################################################
	# BEGIN UTILITY PROCS
	##############################################################################

	#
	# Parse a string of the format "-key val [etc]" into an array
	# ie "-myKey myVal -foo bar" becomes:
	#	argarray(myKey)	= myVal
	#	argarray(foo)	= bar
	#
	proc parse_args {_args _argarray} {
		upvar 1 $_args args
		upvar 1 $_argarray argarray

		unset -nocomplain argarray

		foreach {key value} $args {
			set argarray([string range $key 1 end]) $value
		}

		if {[info exists argarray(array)]} {
			set datalist $argarray(array)
			unset -nocomplain argarray
			array set argarray $datalist
		}

		return
	}

	#
	# Using the configured login credentials, generate HTTP Basic auth headers in
	# list form, suitable for passing to ::http::geturl
	#
	proc authheaders {} {
		unset -nocomplain headerlist

		set auth "Basic [::base64::encode ${::jira::config(username)}:${::jira::config(password)}]"
		lappend headerlist "Authorization" $auth

		lappend headerlist "Content-Type" "application/json"

		return $headerlist
	}

	#
	# Generate the full base URL using the configured server name
	#
	proc baseurl {} {
		set url "https://$::jira::config(server)"
	}

	#
	# Set config values. Pass an arbitrary # of "-key val" arg pairs
	# eg ::jira::config -username myuser -password correcthorsebatterystaple
	#
	proc config {args} {
		::jira::parse_args args argarray
		#parray argarray

		array set ::jira::config [array get argarray]

		return 1
	}
	
	#
	# Execute an API request. Return 1 or 0 to signify request success, and set
	# request metadata to the _result var
	#
	proc raw {url {method GET} _result args} {
		::jira::parse_args args argarray

		upvar 1 $_result result
		unset -nocomplain result

		set httpArgs [list $url -headers [::jira::authheaders] -method $method]
		# Add body if provided
		if {[info exists argarray(body)]} {
			lappend httpArgs -query $argarray(body)
		}
		
		# Do the request
		set token [::http::geturl {*}$httpArgs]
		::http::wait $token

		foreach k {data error status code ncode size meta} {
			set result($k) [::http::$k $token]

			if {([info exists ::jira::config(debug)] && [string is true -strict $::jira::config(debug)]) || [info exists argarray(debug)]} {
				puts $k
				puts [::http::$k $token]
				puts "-- "
			}
		}

		::http::cleanup $token

		if {[info exists result(ncode)] && $result(ncode) >= 200 && $result(ncode) <= 299} {
			return 1
		}

		return 0
	}
	
	##############################################################################
	# END UTILITY PROCS
	##############################################################################
	
	
	
	##############################################################################
	# BEGIN BASIC API PROCS
	#
	# These procs roughly map 1:1 with API methods
	##############################################################################

	#
	# Given a project key (eg "JIRA"), get all known issue types for that project
	# and store them in _result.
	#
	# ex ::jira::getIssueTypes issues -key "JIRA"
	#
	# See https://docs.atlassian.com/jira/REST/cloud/#api/2/issue-getCreateIssueMeta
	#
	proc getIssueTypes {_result args} {
		::jira::parse_args args argarray
		upvar 1 $_result result
		unset -nocomplain result

		set url "[::jira::baseurl]/rest/api/2/issue/createmeta"

		if {[::jira::raw $url GET json]} {
			array set rawresult [::yajl::json2dict $json(data)]
			foreach p $rawresult(projects) {
				unset -nocomplain project
				array set project $p
				if {![info exists argarray(key)] || $argarray(key) eq $project(key)} {
					# parray project
					foreach i $project(issuetypes) {
						unset -nocomplain it
						array set it $i
						set result($it(id)) $i
					}
				}
			}

			# parray result
			return 1
		} else {
			return 0
		}

	}

	#
	# Given an issue identifier (eg "JIRA-123"), get issue data and store in _result
	# Optionally append -getcomments 1 to return comments with issue data.
	#
	# See https://docs.atlassian.com/jira/REST/cloud/#api/2/issue-getIssue
	#
	proc getIssue {number _result args} {
		::jira::parse_args args argarray
		upvar 1 $_result result
		unset -nocomplain result

		set url "[::jira::baseurl]/rest/api/2/issue/$number"

		if {[info exists argarray(getcomments)]} {
			append url "/comment"
		}

		puts "URL $url"

		if {[::jira::raw $url GET json]} {
			array set result [::yajl::json2dict $json(data)]
			# parray result
			return 1
		} else {
			return 0
		}
	}

	#
	# Get all application roles.
	#
	# See https://docs.atlassian.com/jira/REST/cloud/#api/2/applicationrole
	#
	proc getRoles {_result} {
		upvar 1 $_result result
		unset -nocomplain result

		set url "[::jira::baseurl]/rest/api/2/applicationrole"

		if {[::jira::raw $url GET json]} {
			array set result [::yajl::json2dict $json(data)]
			# parray result
			return 1
		} else {
			return 0
		}
	}
	
	#
	# Given an issue identifier (eg "JIRA-123"), get all transitions available to
	# the issue and store in _result.
	#
	# See https://docs.atlassian.com/jira/REST/cloud/#api/2/issue-getTransitions
	#
	proc getTransitions {issueID _result} {
		upvar 1 $_result result
		unset -nocomplain result

		set url "[::jira::baseurl]/rest/api/2/issue/$issueID/transitions"

		if {[::jira::raw $url GET json]} {
			array set result [::yajl::json2dict $json(data)]
			# parray result
			return 1
		} else {
			return 0
		}
	}

	#
	# Given an issue identifier (eg "JIRA-123"), perform the specified transition
	# on the issue. The transition can be specified either by ID or name. Any data
	# returned from the API endpoint is stored in _result.
	#
	# See https://docs.atlassian.com/jira/REST/cloud/#api/2/issue-doTransition
	#
	proc doTransition {issueID transition _result} {
		upvar 1 $_result result
		unset -nocomplain result

		::jira::getTransitions $issueID validTransitionList

		foreach tList $validTransitionList(transitions) {
			unset -nocomplain pt
			array set pt $tList

			if {$pt(name) eq $transition || $pt(id) == $transition} {
				set transitionID $pt(id)
			}
		}

		if {[info exists transitionID]} {
			set url "[::jira::baseurl]/rest/api/2/issue/$issueID/transitions"

			set postdata [::yajl create #auto]
			$postdata map_open
				$postdata map_key transition map_open
					$postdata map_key id string $transitionID
				$postdata map_close
			$postdata map_close
			
			set jsonpost [$postdata get]
			$postdata delete

			if {[::jira::raw $url POST json -body $jsonpost]} {
				array set result [::yajl::json2dict $json(data)]
				# parray result
				return 1
			} else {
				return 0
			}
		} else {
			return 0
		}
	}

	#
	# Multipurpose proc for any API GET method that returns something with an ID.
	# For example, get a project's ID with [::jira::getItemID project "WEB" "key"]
	# Returns the relevant ID or an empty string if something went wrong.
	#
	proc getItemID {type name {field "name"}} {
		set url "[::jira::baseurl]/rest/api/2/$type"

		if {[::jira::raw $url GET json]} {
			foreach el [::yajl::json2dict $json(data)] {
				unset -nocomplain item
				array set item $el
				#parray item
				#puts "-- "
				if {[string tolower $name] eq [string tolower $item($field)]} {
					return $item(id)
				}
			}
		}
		return
	}
	
	#
	# Create a new issue. Issue details should be passed in the _issue array.
	#
	# Required issue fields:
	#	issue(projectID) The key of the project this issue goes in, eg "JIRA:"
	#	issue(issueType) The ID of the issueType to be assigned. See getIssueTypes
	#
	# Other fields may be provided as desired. Array keys should match the field
	# names from JIRA. Examples:
	#	issue(summary) "Hello World!"
	#	issue(description "I'd like to thank the Academy, my parents, blah blah blah"
	#
	# Any data returned by the request will be stored in _result
	#
	proc addIssue {_issue _result args} {
		::jira::parse_args args argarray
		upvar 1 $_issue issue
		upvar 1 $_result result
		unset -nocomplain result

		set url "[::jira::baseurl]/rest/api/2/issue"

		set postdata [::yajl create #auto]

		$postdata map_open
		$postdata string fields map_open

		$postdata string project map_open string id string $issue(projectID) map_close
		foreach item {summary description} {
			if {[info exists issue($item)] && $issue($item) ne ""} {
				$postdata string $item string $issue($item)
			}
		}
		$postdata string issuetype map_open string id string $issue(issueType) map_close

		$postdata map_close
		$postdata map_close

		set jsonpost [$postdata get]
		$postdata delete

		if {([info exists ::jira::config(debug)] && [string is true -strict $::jira::config(debug)]) || [info exists argarray(debug)]} {
			puts "POST $jsonpost"
		}

		if {[::jira::raw $url POST json -body $jsonpost]} {
			array set result [::yajl::json2dict $json(data)]
			return 1
		} else {
			return 0
		}
	}

	#
	# Add a comment to the issue specified by number (eg JIRA-123). The body of
	# the comment should be passed with args, eg -body "This is my comment". Any
	# data returned by the request will be stored in _result
	#
	proc addComment {number _result args} {
		::jira::parse_args args argarray
		upvar 1 $_result result
		unset -nocomplain result

		set url "[::jira::baseurl]/rest/api/2/issue/$number/comment"

		set postdata [::yajl create #auto]
		$postdata map_open string body string $argarray(body)
		# $postdata string visibility map_open string type string role string value string developers map_close

		$postdata string author map_open
		$postdata string self string "https://flightaware.atlassian.net/rest/api/2/user?username=sherron.racz%40flightaware.com"
		$postdata string name string "sherron.racz@flightaware.com"
		$postdata string displayName string "Sherron Racz"
		$postdata string active bool true

		#$postdata string self string "https://flightaware.atlassian.net/rest/api/2/user?username=nugget%40flightaware.com"
		#$postdata string name string "nugget@flightaware.com"
		#$postdata string displayName string "David McNett"
		#$postdata string active bool true

		$postdata map_close

		$postdata map_close
		set jsonpost [$postdata get]
		$postdata delete

		if {([info exists ::jira::config(debug)] && [string is true -strict $::jira::config(debug)]) || [info exists argarray(debug)]} {
			puts "POST $jsonpost"
		}

		if {[::jira::raw $url POST json -body $jsonpost]} {
			array set result [::yajl::json2dict $json(data)]
			# parray result
			return 1
		} else {
			return 0
		}

	}
	
	##############################################################################
	# END BASIC API PROCS
	##############################################################################
	
	
	
	##############################################################################
	# BEGIN MISC PROCS
	#
	# These procs do miscellaneous advanced/fancy stuff, generally wrapping the
	# basic API procs above.
	##############################################################################

	#
	# Construct a regex suitable for searching arbitrary content for apparent JIRA
	# issue identifiers. Issue regex may be manually set using ::jira::config; in
	# that case, the configured regex will be returned unless -force is used. When
	# -force is used or config(issueRegexp) isn't set, all known project keys will
	# be queried and used to construct a regex of the form (KEY1|KEY2|...)-\d+
	#
	proc issueRegexp {args} {
		::jira::parse_args args argarray

		if {[info exists argarray(force)] || ![info exists ::jira::config(issueRegexp)]} {
			set url "[::jira::baseurl]/rest/api/2/project"

			set keylist [list]

			if {[::jira::raw $url GET json]} {
				foreach el [::yajl::json2dict $json(data)] {
					unset -nocomplain item
					array set item $el
					lappend keylist $item(key)
					# parray item
				}
			}
			set ::jira::config(issueRegexp) "([join $keylist "|"])-\\d+"
		}

		return $::jira::config(issueRegexp)

	}
	
	#
	# Convenience proc for generating the URL to an issue
	#
	proc issueURL {issue} {
		return "[::jira::baseurl]/browse/${issue}"
	}

	#
	# Given a bunch of text that might contain JIRA issue identifiers, find each
	# apparently-legit identifier and replace it with a link to the issue. Handles
	# both HTML and Markdown.
	#
	proc addIssueLinks {buf args} {
		::jira::parse_args args argarray
		if {![info exists argarray(format)]} {
			set argarray(format) html
		}

		if {[info exists argarray(class)]} {
			set class "class=\"$argarray(class)\""
		} else {
			set class ""
		}

		switch $argarray(format) {
			html {
				regsub -all [::jira::issueRegexp] $buf "<a href=\"[::jira::issueURL \\0]\" $class>\\0</a>" retbuf
			}

			markdown {
				regsub -all [::jira::issueRegexp] $buf "\[\\0\]([::jira::issueURL \\0])" retbuf
			}

			default {
				set retbuf $buf
			}
		}
		return $retbuf
	}
	
	##############################################################################
	# END MISC PROCS
	##############################################################################
}

package provide jira 1.0
