#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <cstdio>
#include <cstdlib>
int main(int argc,char**argv){@autoreleasepool{
    if(argc!=3)return 2;
    void *library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
    if(!library){fprintf(stderr,"%s\n",dlerror());return 2;}
    auto survived=(bool(*)())dlsym(library,"NTEBootstrapStateSurvived");
    if(!survived)return 2;
    bool actual=survived(),expected=atoi(argv[2])!=0;
    printf("bootstrap resolved_state_survived=%d expected=%d\n",actual,expected);
    return actual==expected?0:1;
}}
