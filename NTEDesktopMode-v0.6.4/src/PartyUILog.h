#pragma once
#ifndef NTE_ENABLE_PARTY_LOGGING
#define NTE_ENABLE_PARTY_LOGGING 0
#endif
namespace PartyUI {
static FILE *logFile=nullptr;
static std::mutex logMutex;
inline void OpenLog(NSString *dir) {
#if NTE_ENABLE_PARTY_LOGGING
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path=[dir stringByAppendingPathComponent:@"party-ui.log"];
    if([[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil] fileSize]>4*1024*1024) {
        NSString *old=[dir stringByAppendingPathComponent:@"party-ui.previous.log"];
        [NSFileManager.defaultManager removeItemAtPath:old error:nil];
        [NSFileManager.defaultManager moveItemAtPath:path toPath:old error:nil];
    }
    logFile=fopen(path.fileSystemRepresentation,"a");
#endif
}
inline void WriteNote(const char *format,...) {
#if NTE_ENABLE_PARTY_LOGGING
    std::lock_guard<std::mutex> lock(logMutex);if(!logFile)return;
    fprintf(logFile,"[%.3f] ",CFAbsoluteTimeGetCurrent());
    va_list args;va_start(args,format);vfprintf(logFile,format,args);va_end(args);
    fputc('\n',logFile);fflush(logFile);
#endif
}
} // namespace PartyUI

// Avoid evaluating diagnostic arguments in a release binary.
#if NTE_ENABLE_PARTY_LOGGING
#define PartyNote(...) PartyUI::WriteNote(__VA_ARGS__)
#else
#define PartyNote(...) ((void)0)
#endif
