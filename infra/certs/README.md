# RDS trust bundle

`rds-ca.pem` is the public Amazon RDS global CA bundle from
https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem.

SHA-256 at inclusion:
`fe45bbebf92ad3e27a583bbb2ddd1553c521ed4d49af5514dc0a40372ea5395c`.

Both application containers include it for certificate-validated PostgreSQL TLS.
Review the official [RDS certificate rotation guidance](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html)
and refresh this bundle as part of image maintenance before CA expiration/rotation.
