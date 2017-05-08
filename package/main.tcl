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
	# eg ::jira::config -username myuser -password correcthorsebatterystaple -server notmyjira.atlassian.net
	#
	proc config {args} {
		::jira::parse_args args argarray
		#parray argarray

		array set ::jira::config [array get argarray]

		return 1
	}

	#
	# Parse issue array into JSON. Custom field processing only handle top level json key-values
	# Example: [list project [list id 1337] labels [list 1223 1222] components [list id 5 id 10]]
	#
	proc issue_array_to_json {_issue _result args} {
		::jira::parse_args args argarray

		upvar 1 $_issue issue

		upvar 1 $_result result
		unset -nocomplain result

		set postdata [::yajl create #auto]
		$postdata map_open string fields map_open

		set basicFields [list summary environment description duedate]
		set listFields [list labels]
		set mapFields [list project issuetype assignee reporter priority components]
		set listMapFields [list components]
		foreach field $basicFields {
			if {[info exists issue($field)]} {
				$postdata string $field string $issue($field)
			}
		}

		foreach field $mapFields {
			if {[info exists issue($field)]} {
				if {[lsearch $listMapFields $field] > -1} {
					$postdata string $field array_open
				} else {
					$postdata string $field map_open
				}


				foreach {key value} $issue($field) {
					if {[lsearch $listMapFields $field] > -1} {
						$postdata map_open
					}

					$postdata string $key string $value;
					
					if {[lsearch $listMapFields $field] > -1} {
						$postdata map_close
					}
				}

				if {[lsearch $listMapFields $field] > -1} {
					$postdata array_close
				} else {
					$postdata map_close
				}

			}
		}

		foreach field $listFields {
			if {[info exists issue($field)]} {
				$postdata string $field array_open
				foreach label $issue(labels) {
					$postdata string $label
				}
				$postdata array_close
			}
		}

		foreach field [array names issue -regexp {^customfield_\d*$}] {
			$postdata string $field string $issue($field)
		}
		
		$postdata map_close
		$postdata map_close
		set result [$postdata get]

		return
	}

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
	# Add a comment to the issue specified by key (eg JIRA-123), also works with
	# id. The body of the comment should be passed with args, eg -body "This is my
	# comment". Any data returned by the request will be stored in _result
	#
	proc addComment {key _result args} {
		::jira::parse_args args argarray
		upvar 1 $_result result
		unset -nocomplain result

		set url "[::jira::baseurl]/rest/api/2/issue/$key/comment"

		if {[info exists argarray(author)]} {
			::jira::parseBasicUser $argarray(userDefinition) author
		} elseif {[info exists argarray(user)]} {
			::jira::parseBasicUser $argarray(userName) author
		} else {
			::jira::parseBasicUser {} author
		}
		
		set postdata [::yajl create #auto]
		$postdata map_open string body string $argarray(body)

		$postdata string author 
		::yajl::add_array_to_json $postdata author

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
	
	#
	# Create a new issue. Issue details should be passed in the _issue array.
	#
	# Required issue fields:
	#	_issue(projectID) The key of the project this issue goes in, eg "JIRA:"
	#	_issue(issueType) The ID of the issueType to be assigned. See getIssueTypes
	#
	# Other fields may be provided as desired. Array keys should match the field
	# names from JIRA. Examples:
	#	_issue(summary) "Hello World!"
	#	_issue(description "I'd like to thank the Academy, my parents, blah blah blah"
	#
	# Any data returned by the request will be stored in _result
	#
	proc addIssue {_issue _result args} {
		::jira::parse_args args argarray
		upvar 1 $_issue issue
		upvar 1 $_result result
		unset -nocomplain result

		set url "[::jira::baseurl]/rest/api/2/issue"
		
		# massage the projectID and issueType fields
		# this is kinda crude but let us retain backwards compatibility
		if {[info exists issue(projectID)]} {
			set issue(project) [list id $issue(projectID)]
			unset issue(projectID)
		}
		
		if {[info exists issue(issueType)]} {
			set issue(issuetype) [list id $issue(issueType)]
			unset issue(issueType)
		}
		
		::jira::issue_array_to_json issue jsonpost

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
	# Create bulk issues. Issues should be a string list of arrays
	# ingestible by issue_array_to_json.
	#
	# Example: description {There is no cow level} projectID 11003 components \
	# {id 11034} summary {AOE II} issuetype {id 10003} project {id 11003} \
	# customfield_10004 {} labels {Zerg Terran Wintoss} issueType 10003
	#
	# Required in each issue:
	#	project   : The key of the project this issue goes in, eg "JIRA:"
	#	issuetype : The ID of the issueType to be assigned. See getIssueTypes
	#
	# Any data returned by the request will be stored in _result
	#
	# https://docs.atlassian.com/jira/REST/cloud/#api/2/issue-createIssues
	#
	proc addIssues {_issueList _result args} {
		::jira::parse_args args argarray
		upvar 1 $_issueList issueList
		upvar 1 $_result result
		unset -nocomplain result

		set url "[::jira::baseurl]/rest/api/2/issue/bulk"

		set postdata [::yajl create #auto]

		set issuesJSON [list]
		foreach issue $issueList {
			array unset issueArr
			array set issueArr $issue
			issue_array_to_json issueArr json
			lappend issuesJSON "$json"
		}

		$postdata map_open
		$postdata string issueUpdates array_open
		set jsonpost [$postdata get]

		append jsonpost [join $issuesJSON ","]

		$postdata clear
		$postdata array_close
		$postdata map_close
		append jsonpost [$postdata get]

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
	# Create a new version (aka release). Details should be passed in the _version
	# array.
	#
	# Required version fields:
	#	_version(name) Name of the version
	#	_version(project) Key of the project this version belongs to, eg "JIRA"
	#
	# Other fields may be passed as required. Examples:
	#	_version(released) 1 or 0 to set the "released" flag
	#	_version(releaseDate) Date of actual release in YYYY-MM-DD format
	#
	# Any data returned by the request will be stored in _result
	#
	proc addVersion {_version _result args} {
		::jira::parse_args args argarray
		upvar 1 $_version version
		upvar 1 $_result result
		unset -nocomplain result
		
		set url "[::jira::baseurl]/rest/api/2/version"
		
		set postdata [::yajl create #auto]
		
		$postdata map_open
			$postdata map_key name string $version(name)
			$postdata map_key project string $version(project)
			
			if {[info exists version(released)]} {
				$postdata map_key released bool $version(released)
			}
			
			if {[info exists version(releaseDate)]} {
				$postdata map_key releaseDate string $version(releaseDate)
			}
			
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
	# Given a username (eg "fred"), get user data and store in _result
	#
	# See https://docs.atlassian.com/jira/REST/cloud/#api/2/user-getUser
	#
	proc getUser {key _result args} {
		::jira::parse_args args argarray
		upvar 1 $_result result
		unset -nocomplain result

		if {$key == ""} {
			set url "[::jira::baseurl]/rest/api/2/myself"
		} else {
			set url "[::jira::baseurl]/rest/api/2/user?username=$key"			
		}


		if {[::jira::raw $url GET json]} {
			array set result [::yajl::json2dict $json(data)]
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

		if {[::jira::raw $url GET json]} {
			array set result [::yajl::json2dict $json(data)]
			# parray result
			return 1
		} else {
			return 0
		}
	}

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
	# Get all versions (aka releases) for a project
	#
	proc getVersions {projectID _result} {
		upvar 1 $_result result
		unset -nocomplain result
		
		set url "[::jira::baseurl]/rest/api/2/project/${projectID}/versions"
		if {[::jira::raw $url GET json]} {
			set result [::yajl::json2dict $json(data)]
			return 1
		} else {
			return 0
		}
	
	}
	

	
	#
	# Tag an issue with a JIRA version. This proc assumes the specified version
	# exists already and the issue isn't already tagged. Any data returned by the
	# request will be stored in _result.
	#
	proc releaseIssue {issueID releaseName _result args} {
		::jira::parse_args args argarray
		upvar 1 $_result result
		unset -nocomplain result
		
		set url "[::jira::baseurl]/rest/api/2/issue/$issueID"
		
		# Build JSON
		set postdata [yajl create #auto]
		$postdata map_open
			$postdata map_key update map_open
				$postdata map_key fixVersions array_open
					$postdata map_open
						$postdata map_key add map_open
							$postdata map_key name string $releaseName
						$postdata map_close
					$postdata map_close
				$postdata array_close
			$postdata map_close
		$postdata map_close

		set jsonpost [$postdata get]
		$postdata delete
		
		if {[::jira::raw $url PUT json -body $jsonpost]} {
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

	#
	# Parse user JSON and generate basic BasicUser JSON.
	#
	proc parseBasicUser {key _result args} {
		::jira::parse_args args argarray

		upvar 1 $_result result
		unset -nocomplain result

		if {[info exists argarray(userDefinition)]} {
			array set result $argarray(userDefinition)
			return
		}

		::jira::getUser $key getUserResult

		set keyMap [list self name displayName active]

		foreach key $keyMap {
			set result($key) $getUserResult($key)
		}

		return
	}

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
	
	##############################################################################
	# END MISC PROCS
	##############################################################################
}

package provide jira 1.0
