
# compile C

This contains a bash script to compile little C projects.


# Personal Interest

I was looking to learn about dll stuff in C and i had an idea about how i wanted to work.

The thing is i like to use the Linux terminal, so i made a compilation script to read the source code (with some considerations) and run all the necessary commands for me.

No magic, it gets the dependencies by reading the "include" instructions right from the source.

The script keeps running and detecting changes (modification dates or missing files) and runs the necessary comands.


# Structure

The expected project structure is something like this:

```txt
projectFolder/
  ├── compileC.sh   <--- add the script right here
  │
  └── src/          <--  source folder
       │
       ├── main.c   <--  main source file
       │
       └── dll.d/   <--- where the script searches for modules (dlls)
            │
            ├── module-A/
            │    └── main.c
            └── module-B/
                 └── main.c
```


# Usage

Copy the script beside your `src` folder, this would look something like this:

```txt
projectFolder/
  ├── compileC.sh   <--  compilation script
  └── src/
       ├── main.c   <--  main source file
       └── ...
```

Run the script:

```bash
./compileC.sh
```

You will get something like this:

```txt
 2023-08-13 22:43:43 : file modified since last time 'main.c'
 2023-08-13 22:43:43 :> CMD: gcc -pass-exit-codes -Wextra -fmax-errors=4 -o ../bin/main.o main.c
 2023-08-13 22:43:43 : PROJECT COMPILED

```

As you can see, the script compiles everything and it show you exactly what commands is running.

And it keeps waiting for changes to recompile stuff.


# Details

Lets say i want to link some libraries like `glfw`, the compilation script should add something like `-lglfw` during execution.
I can automate this by adding some compilation notes related to each `.c` file, creating a `.cnotes` file.

Example:

```txt
projectFolder/
  └── src/
       ├── main.c      <-- compilation target
       └── main.cnotes <-- added stuff
```

And inside the `main.cnotes` file:

```txt
# this is a comment
[libs]
glfw
```

That is all.

I'll add stuff wen needed.


# Example

This project it is more o less structured as a C project that gives a basic idea of what i was looking to do with the compilation script.

Clone and run:

```bash
./compileC.sh
```

you will get something like this:

```txt
 2023-08-13 23:30:34 : file modified since last time 'dll.d/module-A/main.c'
 2023-08-13 23:30:34 : file modified since last time 'lib/tres.h'
 2023-08-13 23:30:34 : file modified since last time 'lib/tres.c'
 2023-08-13 23:30:34 : file modified since last time 'lib/sub/uno.h'
 2023-08-13 23:30:34 : file modified since last time 'lib/sub/uno.c'
 2023-08-13 23:30:34 : file modified since last time 'lib/dos.h'
 2023-08-13 23:30:34 : file modified since last time 'lib/dos.c'
 2023-08-13 23:30:34 : file modified since last time 'main.c'
 2023-08-13 23:30:34 : file modified since last time 'main.cnotes'
 2023-08-13 23:30:34 : file 'lib/dos.c' affects 'lib/tres.c', 'main.c'
 2023-08-13 23:30:34 : file 'lib/dos.h' affects 'lib/dos.c', 'lib/tres.c', 'main.c'
 2023-08-13 23:30:34 : file 'lib/sub/uno.c' affects 'lib/tres.c', 'main.c'
 2023-08-13 23:30:34 : file 'lib/sub/uno.h' affects 'lib/sub/uno.c', 'lib/tres.c', 'main.c'
 2023-08-13 23:30:34 : file 'lib/tres.c' affects 'dll.d/module-A/main.c'
 2023-08-13 23:30:34 : file 'lib/tres.h' affects 'lib/tres.c', 'dll.d/module-A/main.c'
 2023-08-13 23:30:34 : file 'main.cnotes' affects 'main.c'
 2023-08-13 23:30:34 :> CMD: cd '{{ROOT}}/lib'
 2023-08-13 23:30:34 :> CMD: gcc -pass-exit-codes -Wextra -fmax-errors=4 -o ../../bin/lib/dos.o -c dos.c -shared -fpic
 2023-08-13 23:30:34 :> CMD: cd '{{ROOT}}/lib/sub'
 2023-08-13 23:30:34 :> CMD: gcc -pass-exit-codes -Wextra -fmax-errors=4 -o ../../../bin/lib/sub/uno.o -c uno.c -shared -fpic
 2023-08-13 23:30:34 :> CMD: cd '{{ROOT}}/lib'
 2023-08-13 23:30:34 :> CMD: gcc -pass-exit-codes -Wextra -fmax-errors=4 -o ../../bin/lib/tres.o -c tres.c -shared -fpic
 2023-08-13 23:30:35 : compilation notes loaded for 'main.c'
 2023-08-13 23:30:35 :> CMD: gcc -pass-exit-codes -Wextra -fmax-errors=4 -o ../bin/main.o main.c  -ldl -fpic ../bin/lib/sub/uno.o ../bin/lib/dos.o
 2023-08-13 23:30:35 :> CMD: cd '{{ROOT}}/dll.d/module-A'
 2023-08-13 23:30:35 :> CMD: gcc -pass-exit-codes -Wextra -fmax-errors=4 -o ../../../bin/dll.d/module-A.so main.c  -shared -fpic ../../../bin/lib/tres.o ../../../bin/lib/sub/uno.o ../../../bin/lib/dos.o
 2023-08-13 23:30:35 : PROJECT COMPILED

```

Then you can edit the source files and test the "live compilation" mechanics.

Very Nice!


# TODO

- compilation flags using `.cnotes` files
- binary execution arguments using `.cnotes` files


# More Info

Copyright © 2023 Julián Díaz Varela, MIT Licence.


# Licence

MIT
