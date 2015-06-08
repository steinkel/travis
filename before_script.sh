#!/bin/bash

composer self-update

if [ "$PHPCS" = '1' ]; then
	composer require 'cakephp/cakephp-codesniffer:1.*';
	exit 0
fi

#
# Returns the latest reference (either a branch or tag) for any given
# MAJOR.MINOR semantic versioning.
#
latest_ref() {
    # Get the latest tag matching CAKE_VERSION.*
    TAG=$(curl --silent https://api.github.com/repos/cakephp/cakephp/git/refs/tags)
    TAG=$(echo "$TAG" | grep -oEi "tags/$CAKE_VERSION.." | tail -1 | grep -oEi "$CAKE_VERSION..")
    if [ -n "$TAG" ]; then
        echo "$TAG"
        exit 0
    fi
}

if [ "$DB" = "mysql" ]; then
    echo "Using Mysql";
    if [[ -z "$MYSQL_CREATE_DB" ]]; then
        mysql -e 'CREATE DATABASE cakephp_test;';
    else
        eval "$MYSQL_CREATE_DB";
    fi
fi

if [ "$DB" = "pgsql" ]; then
    echo "Using Postgres";
    if [[ -z "$PGSQL_CREATE_DB" ]]; then
        psql -c 'CREATE DATABASE cakephp_test;' -U postgres;
        psql -c 'CREATE SCHEMA default;' -U postgres;
        psql -c 'CREATE SCHEMA test;' -U postgres;
    else
        eval "$PGSQL_CREATE_DB";
    fi
fi

REPO_PATH=$(pwd)
SELF_PATH=$(cd "$(dirname "$0")"; pwd)

# Clone CakePHP repository
CAKE_REF=$(latest_ref)
echo "Using CakePHP version $CAKE_REF"
if [ -z "$CAKE_REF" ]; then
    echo "Found no valid ref to match with version $CAKE_VERSION" >&2
    exit 1
fi

git clone git://github.com/cakephp/cakephp.git -b $CAKE_REF --depth 1 ../cakephp

# Prepare plugin
cd ../cakephp/app

chmod -R 777 tmp

cp -R $REPO_PATH Plugin/$PLUGIN_NAME

mv $SELF_PATH/database.php Config/database.php

COMPOSER_JSON="$(pwd)/Plugin/$PLUGIN_NAME/composer.json"
if [ -f "$COMPOSER_JSON" ]; then
    cp $COMPOSER_JSON ./composer.json;
    composer install --dev --no-interaction --prefer-source
fi

for dep in $REQUIRE; do
    composer require --dev --no-interaction --prefer-source $dep;
done

if [ "$COVERALLS" = '1' ]; then
	composer require --dev satooshi/php-coveralls:dev-master
fi

if [ "$PHPCS" != '1' ]; then
	composer global require 'phpunit/phpunit=3.7.33'
	ln -s ~/.composer/vendor/phpunit/phpunit/PHPUnit ./Vendor/PHPUnit
fi

phpenv rehash

set +H

if [ "$PHPCS" != 1 ]; then
    echo "
    require_once APP . DS . 'vendor' . DS . 'phpunit' . DS . 'phpunit' . DS . 'PHPUnit' . DS . 'Autoload.php';
    " >> Config/bootstrap.php;
fi

echo "CakePlugin::loadAll(array(array('bootstrap' => true, 'routes' => true, 'ignoreMissing' => true)));" >> Config/bootstrap.php

echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<phpunit>
<filter>
    <whitelist>
        <directory suffix=\".php\">Plugin/$PLUGIN_NAME</directory>
        <exclude>
            <directory suffix=\".php\">Plugin/$PLUGIN_NAME/Test</directory>
        </exclude>
    </whitelist>
</filter>
</phpunit>" > phpunit.xml

echo "# for php-coveralls
src_dir: Plugin/$PLUGIN_NAME
coverage_clover: build/logs/clover.xml
json_path: build/logs/coveralls-upload.json" > .coveralls.yml
