# HTTPS

## Firewall 允許 SSH

    sudo ufw allow OpenSSH

## Install Certbot

參考 [certbot instructions](https://certbot.eff.org/instructions)

Ensure that your version of snapd is up to date

    sudo snap install core; sudo snap refresh core

Remove certbot-auto and any Certbot OS packages

    sudo apt-get remove certbot

Install Certbot

    sudo snap install --classic certbot

Prepare the Certbot command

    sudo ln -s /snap/bin/certbot /usr/bin/certbot

get and install your certificates

    sudo certbot --apache

應該要出現成功訊息：
    Your existing certificate has been successfully renewed, and the new certificate
    has been installed.

Test automatic renewal

    sudo certbot renew --dry-run
