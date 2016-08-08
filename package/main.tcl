package require http
package require tls
package require yajltcl
package require base64

::tls::init -ssl2 0 -ssl3 0 -tls1 1
::http::register https 443 ::tls::socket

namespace eval ::jira {
	variable config

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

	proc authheaders {} {
		unset -nocomplain headerlist

		if {[info exists ::jira::config(cookies)] && $::jira::config(cookies) ne ""} {
			lappend headerlist "Cookie" [join $::jira::config(cookies) ";"]
		} else {
			set auth "Basic [::base64::encode ${::jira::config(username)}:${::jira::config(password)}]"
			lappend headerlist "Authorization" $auth
		}

		lappend headerlist "Content-Type" "application/json"

		return $headerlist
	}

	proc baseurl {} {
		set url "https://$::jira::config(server)"
	}

	proc findsession {meta} {
		unset -nocomplain ::jira::config(cookies)

		foreach {key value} $meta {
			if {$key eq "Set-Cookie"} {
				if {[regexp {([^=]+)=([^;]+);} $value _ cname cvalue]} {
					if {$cvalue ne "" && $cvalue ne {""}} {
						lappend ::jira::config(cookies) "$cname=$cvalue"
					}
				}
			}
		}
		return
	}

	proc loginBasic {username password} {
		set url "[::jira::baseurl]/rest/auth/1/session"

		set success [::jira::raw $url authresult]
		if {[string is true -strict $success]} {
			::jira::findsession $authresult(meta)
			return 1
		} else {
			return 0
		}
	}

	proc login {args} {
		::jira::parse_args args argarray

		set username $::jira::config(username)
		set password $::jira::config(password)

		::jira::loginBasic $username $password
	}

	proc config {args} {
		::jira::parse_args args argarray
		#parray argarray

		array set ::jira::config [array get argarray]

		return 1
	}

	proc raw {url _result args} {
		::jira::parse_args args argarray

		upvar 1 $_result result
		unset -nocomplain result

		if {[info exists argarray(post)]} {
			set token [::http::geturl $url -headers [::jira::authheaders] -query $argarray(post)]
		} else {
			set token [::http::geturl $url -headers [::jira::authheaders]]
		}
		::http::wait $token

		foreach k {data error status code ncode size meta} {
			set result($k) [::http::$k $token]

			if {[info exists ::jira::config(debug)] || [info exists argarray(debug)]} {
				puts $k
				puts [::http::$k $token]
				puts "-- "
			}
		}

		::http::cleanup $token

		if {[info exists result(ncode)] && $result(ncode) != 200} {
			return 0
		}

		return 1
	}

	proc getIssue {number _result args} {
		::jira::parse_args args argarray
		upvar 1 $_result result
		unset -nocomplain result

		set url "[::jira::baseurl]/rest/api/2/issue/$number"

		if {[info exists argarray(getcomments)]} {
			append url "/comment"
		}

		puts "URL $url"

		if {[::jira::raw $url json]} {
			array set result [::yajl::json2dict $json(data)]
			# parray result
			return 1
		} else {
			return 0
		}
	}

	proc getRoles {_result} {
		upvar 1 $_result result
		unset -nocomplain result

		set url "[::jira::baseurl]/rest/api/2/applicationrole"

		if {[::jira::raw $url json]} {
			array set result [::yajl::json2dict $json(data)]
			# parray result
			return 1
		} else {
			return 0
		}
	}

	proc getItemID {type name {field "name"}} {
		set url "[::jira::baseurl]/rest/api/2/$type"

		if {[::jira::raw $url json]} {
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

		if {[info exists ::jira::config(debug)] || [info exists argarray(debug)]} {
			puts "POST $jsonpost"
		}

		if {[::jira::raw $url json -post $jsonpost]} {
			array set result [::yajl::json2dict $json(data)]
			# parray result
			return 1
		} else {
			return 0
		}

	}

	proc savecookies {{filename ""}} {
		if {![info exists ::jira::config(cookies)]} {
			return 0
		}
		if {$filename eq ""} {
			set filename [file join $::env(HOME) ".jiraauth"]
		}
		set fh [open $filename "w"]
		puts $fh $::jira::config(cookies)
		close $fh
		return 1
	}

	proc loadcookies {{filename ""}} {
		if {$filename eq ""} {
			set filename [file join $::env(HOME) ".jiraauth"]
		}
		if {![file exists $filename]} {
			return 0
		}
		set fh [open $filename "r"]
		gets $fh ::jira::config(cookies)
		close $fh
		return 1
	}
}

package provide jira 1.0
