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

	proc headers {{username ""} {password ""}} {
		unset -nocomplain headerlist

		if {$username ne "" && $password ne ""} {
			set auth "Basic [::base64::encode ${username}:${password}]"
			lappend headerlist "Authorization" $auth
		}
		lappend headerlist "Content-Type" "application/json"

		return $headerlist
	}

	proc baseurl {} {
		set url "https://$::jira::config(server)"
	}

	proc loginBasic {username password} {
		set url "[::jira::baseurl]/rest/auth/1/session"

		puts "URL: $url"

		set token [::http::geturl $url -headers [::jira::headers $username $password]]
		::http::wait $token

		if {[::http::ncode $token] != 200} {
			::http::cleanup $token
			return 0
		}

		::jira::config -cookie [dict get [::http::meta $token] Set-Cookie]

		foreach k {data error status code ncode size meta} {
			puts $k
			puts [::http::$k $token]
			puts "-- "
		}

		::http::cleanup $token

		puts "all done with login"

		return
	}

	proc login {args} {
		::jira::parse_args args argarray

		set username $::jira::config(username)
		set password $::jira::config(password)

		::jira::loginBasic $username $password
	}

	proc config {args} {
		::jira::parse_args args argarray
		parray argarray

		array set ::jira::config [array get argarray]

		return 1
	}

	proc raw {url _result} {
		upvar 1 $_result result

		unset -nocomplain result

		set username $::jira::config(username)
		set password $::jira::config(password)

		puts "fetching $url"

		set token [::http::geturl $url -headers [::jira::headers $username $password]]
		::http::wait $token

		foreach k {data error status code ncode size meta} {
			set result($k) [::http::$k $token]
		}

		::http::cleanup $token

		if {[info exists result(ncode)] && $result(ncode) != 200} {
			puts "this was a failure"
			return 0
		}

		return 1
	}

	proc getIssue {number _result} {
		upvar 1 $_result result
		unset -nocomplain result

		set url "[::jira::baseurl]/rest/api/2/issue/$number"

		if {[::jira::raw $url json]} {
			array set result [::yajl::json2dict $json(data)]
			parray result
			return 1
		} else {
			return 0
		}
	}
}

package provide jira 1.0
