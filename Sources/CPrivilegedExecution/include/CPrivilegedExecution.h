#ifndef CPrivilegedExecution_h
#define CPrivilegedExecution_h

#include <Security/Authorization.h>
#include <stdio.h>

// Runs one tool with admin rights via Authorization Services.
//
// Swift cannot call `AuthorizationExecuteWithPrivileges` directly:
// the macOS 26 SDK marks it unavailable in Swift, because it was
// deprecated as of macOS 10.9 and earlier. From C the same call is
// only a deprecation warning, so this one-function wrapper carries
// it. The argument vector must be null-terminated; the caller owns
// the strings and the buffer, and the wrapper copies nothing.
// Options are always 0 (no options), matching the Swift caller's
// previous empty-options call.
OSStatus BootcardExecuteWithPrivileges(
    AuthorizationRef authorization,
    const char *pathToTool,
    char *const *arguments,
    FILE **communicationsPipe);

#endif /* CPrivilegedExecution_h */
