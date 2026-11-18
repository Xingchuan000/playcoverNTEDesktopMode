#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <cstdio>
int main(int argc,char **argv){@autoreleasepool{
    if(argc<2)return 2;
    for(int i=1;i<argc;++i){
        void *library=dlopen(argv[i],RTLD_NOW|RTLD_LOCAL);
        if(!library){fprintf(stderr,"dlopen failed: %s\n",dlerror());return 1;}
        printf("standalone Catalyst library load passed: %s\n",argv[i]);
    }
    return 0;
}}
