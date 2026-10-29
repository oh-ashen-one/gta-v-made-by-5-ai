/* Local development-build launcher. No terminal, network listener or installer. */
#include <mach-o/dyld.h>
#include <unistd.h>
#include <limits.h>
#include <libgen.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc,char **argv) {
  char executable[PATH_MAX],directory[PATH_MAX],project[PATH_MAX],stream[PATH_MAX];
  uint32_t length=sizeof(executable);
  if(_NSGetExecutablePath(executable,&length)!=0) return 126;
  strncpy(directory,executable,sizeof(directory)-1); directory[sizeof(directory)-1]=0;
  char *folder=dirname(directory);
  if(snprintf(project,sizeof(project),"%s/../Resources/game",folder)>=(int)sizeof(project)) return 126;
  const char *engine="/Applications/Godot.app/Contents/MacOS/Godot";
  if(access(engine,X_OK)!=0) {fputs("This Studio build requires the installed Godot4.7.1 runtime.\n",stderr);return 127;}
  const char *home=getenv("HOME");int fps=60;
  if(home && snprintf(stream,sizeof(stream),"%s/.cache/gpu-slot/STREAMING",home)<(int)sizeof(stream) && access(stream,F_OK)==0) fps=30;
  const char *cap=getenv("GPU_SLOT_FPS_CAP");
  if(cap) {int requested=atoi(cap);if(requested>0 && requested<fps) fps=requested;}
  char fps_arg[8];snprintf(fps_arg,sizeof(fps_arg),"%d",fps);
  char **args=calloc((size_t)argc+6,sizeof(char*));if(!args)return 126;
  int index=0;args[index++]=(char*)engine;args[index++]="--path";args[index++]=project;
  args[index++]="--max-fps";args[index++]=fps_arg;
  for(int i=1;i<argc;i++) args[index++]=argv[i];args[index]=NULL;
  execv(engine,args);perror("Orchard Reach runtime");free(args);return 127;
}
