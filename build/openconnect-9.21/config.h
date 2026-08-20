/* config.h.  Generated from config.h.in by configure.  */
/* config.h.in.  Generated from configure.ac by autoheader.  */

/* External browser executable */
#define DEFAULT_EXTERNAL_BROWSER "/usr/bin/open"

/* p11-kit proxy */
/* #undef DEFAULT_PKCS11_MODULE */

/* The GnuTLS priority string */
/* #undef DEFAULT_PRIO */

/* Default vpnc-script location */
#define DEFAULT_VPNCSCRIPT "/Users/noahqxs/codes/openconnect-gui/Resources/vpnc-script"

/* Enable NLS support */
/* #undef ENABLE_NLS */

/* endian header include path */
#define ENDIAN_HDR <sys/endian.h>

/* GSSAPI header */
#define GSSAPI_HDR <gssapi/gssapi.h>

/* MinGW has afunix.h */
/* #undef HAVE_AF_UNIX_H */

/* Have alloca.h */
#define HAVE_ALLOCA_H 1

/* Have asprintf() function */
#define HAVE_ASPRINTF 1

/* OpenSSL has BIO_meth_free() function */
/* #undef HAVE_BIO_METH_FREE */

/* Have __builtin_clz() */
#define HAVE_BUILTIN_CLZ 1

/* Define to 1 if you have the <dlfcn.h> header file. */
#define HAVE_DLFCN_H 1

/* Build with DTLS support */
#define HAVE_DTLS 1

/* OpenSSL has DTLS_client_method() function */
/* #undef HAVE_DTLS12 */

/* OpenSSL has dtls1_stop_timer() function */
/* #undef HAVE_DTLS1_STOP_TIMER */

/* OpenSSL has ENGINE support */
/* #undef HAVE_ENGINE */

/* Have epoll */
/* #undef HAVE_EPOLL */

/* Build with ESP support */
#define HAVE_ESP 1

/* Have explicit_bzero() function */
/* #undef HAVE_EXPLICIT_BZERO */

/* Have explicit_memset() function */
/* #undef HAVE_EXPLICIT_MEMSET */

/* Have fdevname_r() function */
/* #undef HAVE_FDEVNAME_R */

/* MinGW declares getenv_s */
/* #undef HAVE_GETENV_S_DECL */

/* Have getline() function */
#define HAVE_GETLINE 1

/* From GnuTLS 3.4.0 */
#define HAVE_GNUTLS_SYSTEM_KEYS 1

/* Have GSSAPI support */
#define HAVE_GSSAPI 1

/* Support Cisco external browser HPKE (ECDH+HKDF+AES-256-GCM) */
#define HAVE_HPKE_SUPPORT 1

/* Have iconv() function */
#define HAVE_ICONV 1

/* Have inet_aton() */
#define HAVE_INET_ATON 1

/* Define to 1 if you have the <inttypes.h> header file. */
#define HAVE_INTTYPES_H 1

/* Have IPV6_PATHMTU socket option */
/* #undef HAVE_IPV6_PATHMTU */

/* Have builtin json-parser package */
#define HAVE_JSON 1

/* Define to 1 if you have the 'log' library (-llog). */
/* #undef HAVE_LIBLOG */

/* Define to 1 if you have the 'nsl' library (-lnsl). */
/* #undef HAVE_LIBNSL */

/* Have libp11 and p11-kit for OpenSSL */
/* #undef HAVE_LIBP11 */

/* Have libpcsclite */
/* #undef HAVE_LIBPCSCLITE */

/* Have libpskc */
/* #undef HAVE_LIBPSKC */

/* Define to 1 if you have the 'socket' library (-lsocket). */
/* #undef HAVE_LIBSOCKET */

/* Have libstoken */
#define HAVE_LIBSTOKEN 1

/* Have localtime_r() function */
#define HAVE_LOCALTIME_R 1

/* Have localtime_s() function */
/* #undef HAVE_LOCALTIME_S */

/* LZ4 was found */
#define HAVE_LZ4 /**/

/* From LZ4 r129 */
#define HAVE_LZ4_COMPRESS_DEFAULT /**/

/* Have memset_s() function */
#define HAVE_MEMSET_S 1

/* Have net/if_utun.h */
#define HAVE_NET_UTUN_H 1

/* Have nl_langinfo() function */
#define HAVE_NL_LANGINFO 1

/* Have. P11. Kit. */
#define HAVE_P11KIT 1

/* Have posix_spawn() function */
#define HAVE_POSIX_SPAWN 1

/* MinGW declares _putenv_s */
/* #undef HAVE_PUTENV_S_DECL */

/* OpenSSL has SSL_CIPHER_find() function */
/* #undef HAVE_SSL_CIPHER_FIND */

/* OpenSSL has SSL_CTX_set_min_proto_version() function */
/* #undef HAVE_SSL_CTX_PROTOVER */

/* Have statfs() function */
#define HAVE_STATFS 1

/* Define to 1 if you have the <stdint.h> header file. */
#define HAVE_STDINT_H 1

/* Define to 1 if you have the <stdio.h> header file. */
#define HAVE_STDIO_H 1

/* Define to 1 if you have the <stdlib.h> header file. */
#define HAVE_STDLIB_H 1

/* Have strcasestr() function */
#define HAVE_STRCASESTR 1

/* Have strchrnul() function */
#define HAVE_STRCHRNUL 1

/* Define to 1 if you have the <strings.h> header file. */
#define HAVE_STRINGS_H 1

/* Define to 1 if you have the <string.h> header file. */
#define HAVE_STRING_H 1

/* Have strndup() function */
#define HAVE_STRNDUP 1

/* On SunOS time() can go backwards */
/* #undef HAVE_SUNOS_BROKEN_TIME */

/* Define to 1 if you have the <sys/stat.h> header file. */
#define HAVE_SYS_STAT_H 1

/* Define to 1 if you have the <sys/types.h> header file. */
#define HAVE_SYS_TYPES_H 1

/* Have Trousers TSS library */
/* #undef HAVE_TROUSERS */

/* TSS2 library */
/* #undef HAVE_TSS2 */

/* Define to 1 if you have the <unistd.h> header file. */
#define HAVE_UNISTD_H 1

/* Have vasprintf() function */
#define HAVE_VASPRINTF 1

/* Have va_copy() */
/* #undef HAVE_VA_COPY */

/* Have vhost */
/* #undef HAVE_VHOST */

/* Have __va_copy() */
/* #undef HAVE___VA_COPY */

/* Define as const if the declaration of iconv() needs const. */
#define ICONV_CONST 

/* if_tun.h include path */
/* #undef IF_TUN_HDR */

/* libproxy header file */
/* #undef LIBPROXY_HDR */

/* Define to the sub-directory where libtool stores uninstalled libraries. */
#define LT_OBJDIR ".libs/"

/* Try to make getenv_s and _putenv_s available */
/* #undef MINGW_HAS_SECURE_API */

/* Using GnuTLS */
#define OPENCONNECT_GNUTLS 1

/* Using OpenSSL */
/* #undef OPENCONNECT_OPENSSL */

/* We need to update to OpenSSL 3.0.0 API */
/* #undef OPENSSL_SUPPRESS_DEPRECATED */

/* Name of package */
#define PACKAGE "openconnect"

/* Define to the address where bug reports for this package should be sent. */
#define PACKAGE_BUGREPORT ""

/* Define to the full name of this package. */
#define PACKAGE_NAME "openconnect"

/* Define to the full name and version of this package. */
#define PACKAGE_STRING "openconnect 9.21"

/* Define to the one symbol short name of this package. */
#define PACKAGE_TARNAME "openconnect"

/* Define to the home page for this package. */
#define PACKAGE_URL ""

/* Define to the version of this package. */
#define PACKAGE_VERSION "9.21"

/* Define to 1 if all of the C89 standard headers exist (not just the ones
   required in a freestanding environment). This macro is provided for
   backward compatibility; new code need not use it. */
#define STDC_HEADERS 1

/* Version number of package */
#define VERSION "9.21"

/* _GNU_SOURCE */
/* #undef _GNU_SOURCE */

/* _NETBSD_SOURCE */
/* #undef _NETBSD_SOURCE */

/* _POSIX_C_SOURCE */
/* #undef _POSIX_C_SOURCE */

/* Windows API version */
/* #undef _WIN32_WINNT */

/* To request memset_s */
#define __STDC_WANT_LIB_EXT1__ 1
