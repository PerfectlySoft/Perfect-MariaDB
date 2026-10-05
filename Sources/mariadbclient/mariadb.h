#ifndef __PERFECT_MARIADB__
#define __PERFECT_MARIADB__
#include <mysql.h>

// MySQL's enum mysql_ssl_mode. libmariadb has no MYSQL_OPT_SSL_MODE; MySQL.setOption maps these
// values onto its own options with perfect_mariadb_set_ssl_mode below.
enum mysql_ssl_mode {
  SSL_MODE_DISABLED = 1,
  SSL_MODE_PREFERRED,
  SSL_MODE_REQUIRED,
  SSL_MODE_VERIFY_CA,
  SSL_MODE_VERIFY_IDENTITY
};

// Returns 0 on success, like mysql_options.
// - DISABLED: no TLS. (libmariadb still uses TLS if MYSQL_OPT_SSL_CA, _CERT, _KEY, _CAPATH or
//   _CIPHER is set.)
// - PREFERRED, REQUIRED: TLS without verifying the certificate. libmariadb quietly falls back to
//   plaintext when the server has no TLS, so MySQL.connect checks REQUIRED itself (only after
//   authenticating; the VERIFY modes fail before that).
// - VERIFY_CA, VERIFY_IDENTITY: TLS with the certificate verified. libmariadb has one switch for
//   both and also checks the host name (except on local connections, from 3.4), so VERIFY_CA is
//   stricter than libmysqlclient's.
static inline int perfect_mariadb_set_ssl_mode(MYSQL *mysql, unsigned int mode) {
  my_bool enforce, verify;
  switch (mode) {
  case SSL_MODE_DISABLED:
    enforce = 0; verify = 0;
    break;
  case SSL_MODE_PREFERRED:
  case SSL_MODE_REQUIRED:
    enforce = 1; verify = 0;
    break;
  case SSL_MODE_VERIFY_CA:
  case SSL_MODE_VERIFY_IDENTITY:
    enforce = 1; verify = 1;
    break;
  default:
    return 1;
  }
  if (mysql_options(mysql, MYSQL_OPT_SSL_ENFORCE, &enforce))
    return 1;
  return mysql_options(mysql, MYSQL_OPT_SSL_VERIFY_SERVER_CERT, &verify);
}
#endif
