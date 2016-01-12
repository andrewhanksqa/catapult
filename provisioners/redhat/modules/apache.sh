source "/catapult/provisioners/redhat/modules/catapult.sh"

# reset httpd log files
if [ -e /var/log/httpd/access_log ]; then
  sudo cat /dev/null > /var/log/httpd/access_log
fi
if [ -e /var/log/httpd/error_log ]; then
  sudo cat /dev/null > /var/log/httpd/error_log
fi

# install apache
sudo yum install -y httpd
sudo systemctl enable httpd.service
sudo systemctl start httpd.service
sudo yum install -y mod_ssl
sudo bash /etc/ssl/certs/make-dummy-cert "/etc/ssl/certs/httpd-dummy-cert.key.cert"

# define the server's servername
# suppress this - httpd: Could not reliably determine the server's fully qualified domain name, using localhost.localdomain. Set the 'ServerName' directive globally to suppress this message
if ! grep -q "ServerName localhost" "/etc/httpd/conf/httpd.conf"; then
   sudo bash -c 'echo "ServerName localhost" >> /etc/httpd/conf/httpd.conf'
fi

# use sites-available, sites-enabled convention. this is a debianism - but the convention is common and easy understand
sudo mkdir -p /etc/httpd/sites-available
sudo mkdir -p /etc/httpd/sites-enabled
if ! grep -q "IncludeOptional sites-enabled/\*.conf" "/etc/httpd/conf/httpd.conf"; then
   sudo bash -c 'echo "IncludeOptional sites-enabled/*.conf" >> "/etc/httpd/conf/httpd.conf"'
fi

# 80: remove the default vhost
sudo cat /dev/null > /etc/httpd/conf.d/welcome.conf

# 443: remove the default vhost
sed -i '/<VirtualHost _default_:443>/,$d' "/etc/httpd/conf.d/ssl.conf"
if ! grep -q "IncludeOptional sites-enabled/\*.conf" "/etc/httpd/conf.d/ssl.conf"; then
   sudo bash -c 'echo "IncludeOptional sites-enabled/*.conf" >> "/etc/httpd/conf.d/ssl.conf"'
fi

# 80/443: create a _default_ catchall
# if the vhost has not been linked, link the vhost
# to test this visit the ip address of the respective environment redhat public ip via http:// or https://
if [ ! -e /var/www/repositories/apache/_default_ ]; then
    sudo ln -s /catapult/repositories/apache/_default_ /var/www/repositories/apache/
fi

# 80/443: enable cors for localdev http response codes from dashboard
if [ "$1" = "dev" ]; then
    cors="SetEnvIf Origin \"^(.*\.?devopsgroup\.io)$\" ORIGIN_SUB_DOMAIN=\$1
    Header set Access-Control-Allow-Origin \"%{ORIGIN_SUB_DOMAIN}e\" env=ORIGIN_SUB_DOMAIN"
else
    cors=""
fi
sudo cat > /etc/httpd/sites-enabled/_default_.conf << EOF
<VirtualHost *:80>
  DocumentRoot /var/www/repositories/apache/_default_/
</VirtualHost>
<IfModule mod_ssl.c>
    <VirtualHost *:443>
        DocumentRoot /var/www/repositories/apache/_default_/
        SSLEngine on
        SSLCertificateFile /etc/ssl/certs/httpd-dummy-cert.key.cert
        SSLCertificateKeyFile /etc/ssl/certs/httpd-dummy-cert.key.cert
    </VirtualHost>
</IfModule>
<Directory "/var/www/repositories/apache/_default_/">
    $cors
</Directory>
EOF

# reload apache
sudo systemctl reload httpd.service
sudo systemctl status httpd.service
