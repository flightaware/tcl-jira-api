package require http
package require tls

::tls::init -ssl2 0 -ssl3 0 -tls1 1

namespace eval ::jira {
	proc parse_args {_args _argarray} {
		upvar 1 $_args args
		upvar 1 $_argarray argarray

		unset -nocomplain argarray

		foreach {key value} $args {
			set argarray($key) $value
		}

		return
	}

	proc login {args} {
		::jira::parse_args args argarray

		parray argarray

	}
}

package provide jira 1.0
