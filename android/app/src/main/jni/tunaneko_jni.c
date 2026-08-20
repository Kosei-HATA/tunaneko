// JNI bridge between tunaneko (Kotlin) and libopenconnect.
//
// One VPN connection at a time (enforced by Android VpnService anyway),
// so the run context is a single global.
#include <jni.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include <stdarg.h>
#include <android/log.h>
#include <openconnect.h>

#define NLOG(...) __android_log_print(ANDROID_LOG_DEBUG, "tunaneko-native", __VA_ARGS__)

static JavaVM *g_vm;

typedef struct {
    struct openconnect_info *vpninfo;
    jobject callbacks;          // global ref to CoreCallbacks
    jmethodID onLog;
    jmethodID onCertCheck;      // (String fingerprintHex, String reason) -> boolean
    jmethodID onProtect;        // (int fd) -> boolean
    jmethodID onSetupTun;       // (TunConfig) -> int (fd)
    jmethodID onAuthError;      // (String)
    char *username;
    char *password;
    char *cert_pin_hex;         // NULL = TOFU not yet pinned
    int cancel_w;               // write end of cancel pipe
    int tun_fd;                 // detached from ParcelFileDescriptor; we close it
} run_ctx;

static run_ctx *g_ctx;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

// All libopenconnect callbacks fire on the nativeRun thread, which is a
// live JVM thread (attached by nativeRun itself). Attaching/detaching per
// callback aborts ART (DetachCurrentThread with pending state), so we just
// fetch the current env and never detach inside callbacks.
static JNIEnv *get_env(void) {
    JNIEnv *env = NULL;
    if ((*g_vm)->GetEnv(g_vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
        (*g_vm)->AttachCurrentThread(g_vm, &env, NULL);
    }
    return env;
}

// clear any pending JNI exception so it can't leak into the C library
static void clear_exc(JNIEnv *env) {
    if ((*env)->ExceptionCheck(env))
        (*env)->ExceptionClear(env);
}

// ---- libopenconnect callbacks ------------------------------------------------

static void cb_progress(void *privdata, int level, const char *fmt, ...) {
    (void)privdata;
    char buf[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    NLOG("progress: %s", buf);
    JNIEnv *env = get_env();
    jstring s = (*env)->NewStringUTF(env, buf);
    (*env)->CallVoidMethod(env, g_ctx->callbacks, g_ctx->onLog, level, s);
    clear_exc(env);
    (*env)->DeleteLocalRef(env, s);
}

static int cb_validate_peer_cert(void *privdata, const char *reason) {
    (void)privdata;
    // stored pin (hash string from a previous session) → let the library
    // compare; it handles hash-function upgrades correctly.
    if (g_ctx->cert_pin_hex &&
        openconnect_check_peer_cert_hash(g_ctx->vpninfo, g_ctx->cert_pin_hex) == 0)
        return 0;

    // TOFU or mismatch: let Kotlin decide (it shows/persists the hash)
    const char *hash = openconnect_get_peer_cert_hash(g_ctx->vpninfo);
    JNIEnv *env = get_env();
    jstring fp = (*env)->NewStringUTF(env, hash ? hash : "");
    jstring rs = (*env)->NewStringUTF(env, reason ? reason : "");
    jboolean ok = (*env)->CallBooleanMethod(env, g_ctx->callbacks, g_ctx->onCertCheck, fp, rs);
    clear_exc(env);
    (*env)->DeleteLocalRef(env, fp);
    (*env)->DeleteLocalRef(env, rs);
    return ok ? 0 : -1;
}

static int cb_process_auth_form(void *privdata, struct oc_auth_form *form) {
    (void)privdata;
    if (form->error) {
        JNIEnv *env = get_env();
        jstring e = (*env)->NewStringUTF(env, form->error);
        (*env)->CallVoidMethod(env, g_ctx->callbacks, g_ctx->onAuthError, e);
    clear_exc(env);
        (*env)->DeleteLocalRef(env, e);
    }
    for (struct oc_form_opt *opt = form->opts; opt; opt = opt->next) {
        if (opt->type == OC_FORM_OPT_PASSWORD) {
            openconnect_set_option_value(opt, g_ctx->password);
        } else if (opt->type == OC_FORM_OPT_TEXT && opt->name &&
                   strcmp(opt->name, "username") == 0) {
            openconnect_set_option_value(opt, g_ctx->username);
        }
        // select/group options: keep server default
    }
    return 0;
}

static int cb_write_new_config(void *privdata, const char *buf, int buflen) {
    (void)privdata; (void)buf; (void)buflen;
    return 0; // we don't persist server-provided config
}

static void cb_protect_socket(void *privdata, int fd) {
    (void)privdata;
    JNIEnv *env = get_env();
    (*env)->CallBooleanMethod(env, g_ctx->callbacks, g_ctx->onProtect, fd);
    clear_exc(env);
}

static void cb_setup_tun(void *privdata) {
    (void)privdata;
    struct openconnect_info *vi = g_ctx->vpninfo;
    const struct oc_ip_info *ip = NULL;
    if (openconnect_get_ip_info(vi, &ip, NULL, NULL) != 0 || !ip)
        return;

    JNIEnv *env = get_env();

    jstring addr = (*env)->NewStringUTF(env, ip->addr ? ip->addr : "");
    jstring netmask = (*env)->NewStringUTF(env, ip->netmask ? ip->netmask : "");
    jstring domain = (*env)->NewStringUTF(env, ip->domain ? ip->domain : "");

    // DNS servers
    jclass strClass = (*env)->FindClass(env, "java/lang/String");
    jobjectArray dns = (*env)->NewObjectArray(env, 3, strClass, NULL);
    for (int i = 0; i < 3; i++) {
        jstring s = (*env)->NewStringUTF(env, ip->dns[i] ? ip->dns[i] : "");
        (*env)->SetObjectArrayElement(env, dns, i, s);
        (*env)->DeleteLocalRef(env, s);
    }

    jint fd = (*env)->CallIntMethod(env, g_ctx->callbacks, g_ctx->onSetupTun,
                                    addr, netmask, dns, (jint)ip->mtu, domain);
    clear_exc(env);

    (*env)->DeleteLocalRef(env, addr);
    (*env)->DeleteLocalRef(env, netmask);
    (*env)->DeleteLocalRef(env, domain);
    (*env)->DeleteLocalRef(env, dns);
    (*env)->DeleteLocalRef(env, strClass);

    if (fd >= 0) {
        // fd ownership was transferred via ParcelFileDescriptor.detachFd()
        // on the Kotlin side — the library/we may close it freely (fdsan
        // no longer tracks it).
        g_ctx->tun_fd = fd;
        openconnect_setup_tun_fd(vi, fd);
    }
}

// ---- JNI entry points ---------------------------------------------------------

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
    (void)reserved;
    g_vm = vm;
    return JNI_VERSION_1_6;
}

JNIEXPORT jint JNICALL
Java_com_tunaneko_core_NativeCore_nativeRun(JNIEnv *env, jclass clazz,
        jstring host, jstring username, jstring password, jstring certPin,
        jobject callbacks) {
    (void)clazz;

    run_ctx ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.tun_fd = -1;
    ctx.cancel_w = -1;
    ctx.callbacks = (*env)->NewGlobalRef(env, callbacks);

    jclass cbClass = (*env)->GetObjectClass(env, callbacks);
    ctx.onLog = (*env)->GetMethodID(env, cbClass, "onLog", "(ILjava/lang/String;)V");
    ctx.onCertCheck = (*env)->GetMethodID(env, cbClass, "onCertCheck",
                                          "(Ljava/lang/String;Ljava/lang/String;)Z");
    ctx.onProtect = (*env)->GetMethodID(env, cbClass, "onProtect", "(I)Z");
    ctx.onAuthError = (*env)->GetMethodID(env, cbClass, "onAuthError", "(Ljava/lang/String;)V");
    ctx.onSetupTun = (*env)->GetMethodID(env, cbClass, "onSetupTun",
        "(Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;ILjava/lang/String;)I");

    NLOG("methodIDs: onLog=%p cert=%p protect=%p authErr=%p setupTun=%p",
         ctx.onLog, ctx.onCertCheck, ctx.onProtect, ctx.onAuthError, ctx.onSetupTun);

    const char *u = (*env)->GetStringUTFChars(env, username, NULL);
    const char *p = (*env)->GetStringUTFChars(env, password, NULL);
    ctx.username = u ? strdup(u) : strdup("");
    ctx.password = p ? strdup(p) : strdup("");
    if (u) (*env)->ReleaseStringUTFChars(env, username, u);
    if (p) (*env)->ReleaseStringUTFChars(env, password, p);
    const char *pin = certPin ? (*env)->GetStringUTFChars(env, certPin, NULL) : NULL;
    ctx.cert_pin_hex = pin ? strdup(pin) : NULL;
    if (pin) (*env)->ReleaseStringUTFChars(env, certPin, pin);

    pthread_mutex_lock(&g_lock);
    if (g_ctx != NULL) {
        // single session at a time: a stale nativeRun is still alive
        pthread_mutex_unlock(&g_lock);
        (*env)->DeleteGlobalRef(env, ctx.callbacks);
        return -100 /* -EBUSY */;
    }
    g_ctx = &ctx;
    pthread_mutex_unlock(&g_lock);

    struct openconnect_info *vi = openconnect_vpninfo_new(
        "tunaneko", cb_validate_peer_cert, cb_write_new_config,
        cb_process_auth_form, cb_progress, &ctx);
    ctx.vpninfo = vi;

    openconnect_set_protocol(vi, "anyconnect");
    openconnect_set_loglevel(vi, PRG_INFO);
    openconnect_set_protect_socket_handler(vi, cb_protect_socket);
    openconnect_set_setup_tun_handler(vi, cb_setup_tun);
    // library-owned command pipe: both ends are closed by vpninfo_free,
    // avoiding fd-reuse double-close hazards entirely
    ctx.cancel_w = openconnect_setup_cmd_pipe(vi);
    openconnect_init_ssl();

    const char *h = (*env)->GetStringUTFChars(env, host, NULL);
    int ret = openconnect_parse_url(vi, (char *)h);
    (*env)->ReleaseStringUTFChars(env, host, h);

    // CLI-equivalent sequence: auth (obtain cookie) → CSTP → DTLS → mainloop.
    // mainloop alone does NOT connect; it only runs the packet loop.
    if (ret == 0)
        ret = openconnect_obtain_cookie(vi);
    if (ret == 0)
        ret = openconnect_make_cstp_connection(vi);
    if (ret == 0) {
        // PoC: DTLS disabled — gnutls rejects the server's DTLS records as
        // oversized (EMSGSIZE) against the negotiated MTU on Android.
        // CSTP-only works; DTLS can be re-enabled after MTU tuning.
        openconnect_disable_dtls(vi);
        ret = openconnect_mainloop(vi, 300, 10);
    }

    // cleanup — clear g_ctx FIRST so nativeCancel can never write to a
    // closed (possibly reused) fd. The cmd pipe is closed by vpninfo_free.
    pthread_mutex_lock(&g_lock);
    g_ctx = NULL;
    pthread_mutex_unlock(&g_lock);
    if (ctx.tun_fd >= 0)
        close(ctx.tun_fd);   // detached fd: safe, unowned
    openconnect_vpninfo_free(vi);
    (*env)->DeleteGlobalRef(env, ctx.callbacks);
    free(ctx.username);
    if (ctx.password) {
        // zero before free (bionic lacks explicit_bzero; volatile loop)
        volatile char *z = (volatile char *)ctx.password;
        size_t n = strlen(ctx.password);
        while (n--) *z++ = 0;
        free(ctx.password);
    }
    free(ctx.cert_pin_hex);
    return ret;
}

JNIEXPORT void JNICALL
Java_com_tunaneko_core_NativeCore_nativeCancel(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    pthread_mutex_lock(&g_lock);
    if (g_ctx && g_ctx->cancel_w >= 0) {
        char c = OC_CMD_CANCEL;
        (void)!write(g_ctx->cancel_w, &c, 1);
    }
    pthread_mutex_unlock(&g_lock);
}
