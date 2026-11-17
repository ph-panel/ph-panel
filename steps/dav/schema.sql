-- PH-PANEL calendars and contacts [62]: the SabreDAV tables (from sabre/dav 4.7.1 examples/sql, BSD-3-Clause) plus the sharing table of address books.

CREATE TABLE calendarobjects (
    id integer primary key asc NOT NULL,
    calendardata blob NOT NULL,
    uri text NOT NULL,
    calendarid integer NOT NULL,
    lastmodified integer NOT NULL,
    etag text NOT NULL,
    size integer NOT NULL,
    componenttype text,
    firstoccurence integer,
    lastoccurence integer,
    uid text,
    UNIQUE(calendarid,uri)
);
CREATE INDEX calendarid_time ON calendarobjects (calendarid, firstoccurence);

CREATE TABLE calendars (
    id integer primary key asc NOT NULL,
    synctoken integer DEFAULT 1 NOT NULL,
    components text NOT NULL
);

CREATE TABLE calendarinstances (
    id integer primary key asc NOT NULL,
    calendarid integer NOT NULL,
    principaluri text NULL,
    access integer NOT NULL DEFAULT '1',
    displayname text,
    uri text NOT NULL,
    description text,
    calendarorder integer,
    calendarcolor text,
    timezone text,
    transparent bool,
    share_href text,
    share_displayname text,
    share_invitestatus integer DEFAULT '2',
    UNIQUE (principaluri, uri),
    UNIQUE (calendarid, principaluri),
    UNIQUE (calendarid, share_href)
);

CREATE TABLE calendarchanges (
    id integer primary key asc NOT NULL,
    uri text,
    synctoken integer NOT NULL,
    calendarid integer NOT NULL,
    operation integer NOT NULL
);

CREATE INDEX calendarid_synctoken ON calendarchanges (calendarid, synctoken);

CREATE TABLE calendarsubscriptions (
    id integer primary key asc NOT NULL,
    uri text NOT NULL,
    principaluri text NOT NULL,
    source text NOT NULL,
    displayname text,
    refreshrate text,
    calendarorder integer,
    calendarcolor text,
    striptodos bool,
    stripalarms bool,
    stripattachments bool,
    lastmodified int,
    UNIQUE(principaluri, uri)
);

CREATE TABLE schedulingobjects (
    id integer primary key asc NOT NULL,
    principaluri text NOT NULL,
    calendardata blob,
    uri text NOT NULL,
    lastmodified integer,
    etag text NOT NULL,
    size integer NOT NULL,
    UNIQUE(principaluri, uri)
);

CREATE TABLE addressbooks (
    id integer primary key asc NOT NULL,
    principaluri text NOT NULL,
    displayname text,
    uri text NOT NULL,
    description text,
    synctoken integer DEFAULT 1 NOT NULL,
    UNIQUE(principaluri, uri)
);


CREATE TABLE cards (
    id integer primary key asc NOT NULL,
    addressbookid integer NOT NULL,
    carddata blob,
    uri text NOT NULL,
    lastmodified integer,
    etag text,
    size integer,
    UNIQUE(addressbookid, uri)
);

CREATE TABLE addressbookchanges (
    id integer primary key asc NOT NULL,
    uri text,
    synctoken integer NOT NULL,
    addressbookid integer NOT NULL,
    operation integer NOT NULL
);

CREATE INDEX addressbookid_synctoken ON addressbookchanges (addressbookid, synctoken);

CREATE TABLE principals (
    id INTEGER PRIMARY KEY ASC NOT NULL,
    uri TEXT NOT NULL,
    email TEXT,
    displayname TEXT,
    UNIQUE(uri)
);

CREATE TABLE groupmembers (
    id INTEGER PRIMARY KEY ASC NOT NULL,
    principal_id INTEGER NOT NULL,
    member_id INTEGER NOT NULL,
    UNIQUE(principal_id, member_id)
);

CREATE TABLE propertystorage (
    id integer primary key asc NOT NULL,
    path text NOT NULL,
    name text NOT NULL,
    valuetype integer NOT NULL,
    value string
);

CREATE UNIQUE INDEX path_property ON propertystorage (path, name);

CREATE TABLE addressbook_shares (
    id integer primary key asc NOT NULL,
    addressbookid integer NOT NULL,
    principaluri text NOT NULL,
    access integer NOT NULL DEFAULT 2,
    UNIQUE(addressbookid, principaluri)
);
CREATE TABLE ph_meta (k text PRIMARY KEY NOT NULL, v text);
