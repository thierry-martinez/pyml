#if __APPLE__
  #define PLATFORM_NAME Mac
#elif __linux__
  #define PLATFORM_NAME Linux
#elif defined(WIN32) || defined(_WIN32)
  #define PLATFORM_NAME Windows
  #define WIN_HANDLE_FD
#else
  #error "Unknown platform"
#endif

type t = Linux | Windows | Mac

let os = PLATFORM_NAME

#ifdef WIN_HANDLE_FD
  external fd_of_int : int -> Unix.file_descr = "win_handle_fd"
#else
  external fd_of_int : int -> Unix.file_descr = "%identity"
#endif
