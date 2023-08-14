
#include "lib/sub/uno.h"
#include "lib/dos.h"

#include <stdlib.h>
#include <stdio.h>
#include <dlfcn.h>

int main( int argc, char **argv ) {

	void *handle;
	double ( *call )( void );
	char *error;

	handle = dlopen( "bin/dll.d/module-A.so", RTLD_LAZY );
	if( !handle ) {
		fputs( dlerror(), stderr );
		exit( 1 );
	};

	call = dlsym( handle, "demo" );
	if( ( error = dlerror() ) != NULL ) {
		fputs( error, stderr );
		exit( 1 );
	};

	call();

	printf( "uno: %d\n", uno() );
	printf( "dos: %d\n", dos() );

	dlclose( handle );
};
