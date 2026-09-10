package utils

import (
	"fmt"
	"io"
	"log"
	"os"
)

var (
	debugLog *log.Logger
	verbose  bool
)

func EnableDebug() {
	EnableDebugWithWriter(os.Stderr)
}

// EnableDebugWithWriter enables diagnostics while sending them to w. It is
// used by embedders (such as the iOS bridge) that must retain useful transport
// errors for an in-app log viewer as well as writing them to stderr.
func EnableDebugWithWriter(w io.Writer) {
	if w == nil {
		w = os.Stderr
	}
	verbose = true
	debugLog = log.New(w, "", log.LstdFlags|log.Lmicroseconds)
	log.SetFlags(log.LstdFlags | log.Lmicroseconds | log.Lshortfile)
}

func Debugf(format string, args ...interface{}) {
	if verbose {
		debugLog.Output(2, fmt.Sprintf(format, args...))
	}
}

func IsVerbose() bool {
	return verbose
}
