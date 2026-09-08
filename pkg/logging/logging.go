package logging

import "fmt"
import "time"

import klog "k8s.io/klog/v2"

// TRACE is the log level for trace messages.
var TRACE int = 0

// DEBUG is the log level for debug messages.
var DEBUG = 1

// INFO is the log level for info messages.
var INFO = 2

// WARNING is the log level for warning messages.
var WARNING = 3

// ERROR is the log level for error messages.
var ERROR = 4

// Logger is the shared package-level logger used by the load test.
var Logger = logger{}

// Logger setup
type logger struct {
	Level    int  // 0 = trace, 1 = debug, 2 = info, 3 = warning, 4 = error, 5 = fatal
	FailFast bool // Should even errors be fatal?
}

// Trace logs a trace-level message when the logger level is TRACE or lower.
func (l *logger) Trace(msg string, params ...interface{}) {
	if l.Level <= TRACE {
		klog.Infof("TRACE "+msg, params...)
	}
}

// Debug logs a debug-level message when the logger level is DEBUG or lower.
func (l *logger) Debug(msg string, params ...interface{}) {
	if l.Level <= DEBUG {
		klog.Infof("DEBUG "+msg, params...)
	}
}

// Info logs an info-level message when the logger level is INFO or lower.
func (l *logger) Info(msg string, params ...interface{}) {
	if l.Level <= INFO {
		klog.Infof("INFO "+msg, params...)
	}
}

// Warning logs a warning-level message when the logger level is WARNING or lower.
func (l *logger) Warning(msg string, params ...interface{}) {
	if l.Level <= WARNING {
		klog.Infof("WARNING "+msg, params...)
	}
}

// Error logs an error-level message when the logger level is ERROR or lower.
func (l *logger) Error(msg string, params ...interface{}) {
	if l.Level <= ERROR {
		if l.FailFast {
			klog.Fatalf("ERROR(fatal)"+msg, params...)
		} else {
			klog.Errorf("ERROR "+msg, params...)
		}
	}
}

// Fatal logs a fatal message and terminates the process after stopping measurements.
func (l *logger) Fatal(msg string, params ...interface{}) {
	MeasurementsStop()
	klog.Fatalf("FATAL "+msg, params...)
}

// Log test failure with error code to CSV file so we can compile a statistic later
func (l *logger) Fail(errCode int, msg string, params ...interface{}) error {
	errorMessage := fmt.Sprintf("FAIL(%d): %s", errCode, msg)
	klog.Infof(errorMessage, params...)
	data := ErrorEntry{
		Timestamp: time.Now(),
		Code:      errCode,
		Message:   fmt.Sprintf(errorMessage, params...),
	}
	errorsQueue <- data
	return fmt.Errorf(errorMessage, params...)
}
