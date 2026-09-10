package main

import "time"

// Small time helpers kept in one place so the proxy file stays about protocol
// handling. Go's c-archive build has no issue with these, but naming them keeps
// the intent obvious at the call sites.

func nowPlus(ns int64) time.Time {
	return time.Now().Add(time.Duration(ns))
}

func noDeadline() time.Time {
	return time.Time{}
}

func timeAfter(seconds int) <-chan time.Time {
	return time.After(time.Duration(seconds) * time.Second)
}
