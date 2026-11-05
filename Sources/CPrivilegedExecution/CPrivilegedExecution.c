#include "CPrivilegedExecution.h"

OSStatus BootcardExecuteWithPrivileges(
    AuthorizationRef authorization,
    const char *pathToTool,
    char *const *arguments,
    FILE **communicationsPipe) {
    return AuthorizationExecuteWithPrivileges(
        authorization, pathToTool, 0, arguments, communicationsPipe);
}
