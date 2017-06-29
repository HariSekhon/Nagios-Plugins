#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-06-20 17:56:29 +0200 (Tue, 20 Jun 2017)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn
#  and optionally send me feedback
#
#  https://www.linkedin.com/in/harisekhon
#

"""

Nagios Plugin to check an Atlas entity via the HTTP Rest API of an Atlas Metadata server instance

Tests:

    - entity exists
    - entity status = ACTIVE
    - optional:
        - type - entity is of specified type (eg. 'DB' or 'hdfs_path')
        - tags - specified tag(s) are assigned to entity (eg. PII - important as Ranger ACLs can allow or deny access
                 based on these tags)
    - verbose mode will also show modified date and version

Finding an entity by name adds an O(n) operation to first find the guid by scanning all entities so you may need
to increase timeouts and reduce check frequency if you have a lot of entities stored in Atlas.

I strongly recommend that you find the entity one time using --list to get the ID and then run the check using the ID
returned because it's much more efficient - it saves one query to find and return all entities as well as having to
iterate on every returned entity until it can find a matching name or throw a critical result if no matching name is
found. Those extra operations to find by name won't scale well on a large setup due to the O(n) nature of the work
required increasing proportionally as more and more metadata entities are stored in Atlas over time.

Tested on Atlas 0.8.0 on Hortonworks HDP 2.6.0

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import os
import sys
import traceback
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import ERRORS, CriticalError, UnknownError, support_msg_api
    from harisekhon.utils import isList, validate_chars, plural, log_option
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.4.3'


class CheckAtlasEntity(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckAtlasEntity, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Atlas'
        self.default_port = 21000
        self.json = True
        self.msg = 'Atlas entity'
        self.entity_name = None
        self.entity_id = None
        self._type = None
        self.tags = None
        self.traits = None
        self.list_entities = False
        # HDP data governance doc says /v2/entities and /v2/entities/guids?guid=... but these don't work
        self.path = '/api/atlas/v1/entities'

    def add_options(self):
        super(CheckAtlasEntity, self).add_options()
        self.add_opt('-E', '--entity-name', help='Entity name in find in Atlas')
        self.add_opt('-I', '--entity-id',
                     help='Entity ID to find in Atlas (prefer this over name, see --help description)')
        self.add_opt('-T', '--type', help='Type to expect entity to have')
        self.add_opt('-A', '--tags', help='Tag(s) to expect entity to have, comma separated')
        #self.add_opt('-R', '--traits', help='Trait(s) to expect entity to have, comma separated')
        self.add_opt('-l', '--list', action='store_true', help='List entities')

    def process_options(self):
        super(CheckAtlasEntity, self).process_options()
        self.entity_name = self.get_opt('entity_name')
        self.entity_id = self.get_opt('entity_id')
        self.list_entities = self.get_opt('list')
        if not self.list_entities:
            if not self.entity_name and not self.entity_id:
                self.usage('must supply an --entity-id/--entity-name to find or --list-entities')
            if self.entity_name and self.entity_id:
                self.usage('cannot specify both --entity-id and --entity-name as the search criteria ' +
                           'at the same time, prefer --entity-id it\'s more efficient')
            if self.entity_name:
                # this can contain pretty much anything including /haritest
                #validate_chars(self.entity_name, 'entity name', r'A-Za-z0-9\.\,_-')
                log_option('entity_name', self.entity_name)
            if self.entity_id:
                validate_chars(self.entity_id, 'entity id', r'A-Za-z0-9-')
                # v1
                self.path += '/{0}'.format(self.entity_id)
                # v2
                #self.path += '/guids?guid={0}'.format(self.entity_id)
        self._type = self.get_opt('type')
        self.tags = self.get_opt('tags')
        #self.traits = self.get_opt('traits')
        if self._type:
            validate_chars(self._type, 'type', r'A-Za-z0-9_-')
        if self.tags:
            self.tags = sorted(self.tags.split(','))
            for tag in self.tags:
                validate_chars(tag, 'tag', r'A-Za-z0-9\.\,_-')
        if self.traits:
            self.traits = sorted(self.traits.split(','))
            for trait in self.traits:
                validate_chars(trait, 'trait', r'A-Za-z0-9\.\,_-')

    def get_key(self, json_data, key):
        try:
            return json_data[key]
        except KeyError:
            raise UnknownError('\'{0}\' key was not returned in output from '.format(key) +
                               'Atlas metadata server instance at {0}:{1}. {2}'\
                               .format(self.host, self.port, support_msg_api()))

    def parse_json(self, json_data):
        if not isList(json_data):
            raise UnknownError('non-list returned by Atlas metadata server instance at {0}:{1}! {2}'\
                               .format(self.host, self.port, support_msg_api()))
        if len(json_data) < 1:
            raise CriticalError('no entities found!')
        if self.list_entities:
            print('=' * 100)
            print('{0:40} {1:25} {2}'.format('ID', 'Type', 'Name'))
            print('=' * 100)
            for entity in json_data:
                name = self.get_key(entity, 'name')
                _id = self.get_key(entity, 'id')
                _type = self.get_key(entity, 'type')
                print('{0:40} {1:25} {2}'.format(_id, _type, name))
            sys.exit(ERRORS['UNKNOWN'])
        if self.entity_id:
            if len(json_data) > 1:
                raise CriticalError('more than one matching entity returned!')
            json_data = json_data[0]
        elif self.entity_name:
            for entity in json_data:
                if self.entity_name == self.get_key(entity, 'name'):
                    # Recursion - a bit too clever but convenient
                    self.entity_name = None
                    self.entity_id = self.get_key(entity, 'id')
                    self.path += '/{0}'.format(self.entity_id)
                    req = self.query()
                    self.process_json(req.content)
                    # escape recursion
                    return
            raise CriticalError("entity with name '{name}' not found!".format(name=self.entity_name))
        name = self.get_key(json_data, 'name')
        state = self.get_key(json_data, 'state')
        # available for HDFS path but not DB
        #path = self.get_key(json_data, 'path')
        _type = self.get_key(json_data, 'type')
        tags = []
        if 'trait_names' in json_data:
            tags = self.get_key(json_data, 'trait_names')
        #traits = self.get_key(json_data, 'traits')
        version = self.get_key(json_data, 'version')
        modified_date = self.get_key(json_data, 'modified_time')
        self.msg += " '{name}' exists, state='{state}'".format(name=name, state=state)
        if state != 'ACTIVE':
            self.critical()
            self.msg += " (expected 'ACTIVE')"
        self.msg += ", type='{type}'".format(type=_type)
        self.check_type(_type)
        #if self.verbose:
        self.msg += ", tags='{tags}'".format(tags=','.join(tags))
        self.check_missing_tags(tags)
        #if self.verbose:
        #self.msg += ", traits='{traits}'".format(traits=','.join(traits))
        #self.check_missing_traits(traits)
        if self.verbose:
            self.msg += ", modified_date='{modified_date}', version='{version}'".format(
                modified_date=modified_date,
                version=version
            )

    def check_type(self, _type):
        if self._type and self._type != _type:
            self.critical()
            self.msg += " (expected type '{type}')".format(type=self._type)
            return False
        return True

    def check_missing_tags(self, tags):
        if not isList(tags):
            raise UnknownError('tags non-list returned. {0}'.format(support_msg_api()))
        if self.tags:
            missing_tags = []
            #tags = [t.lower() for t in tags]
            for tag in self.tags:
                #if tag.lower() not in tags:
                if tag not in tags:
                    missing_tags.append(tag)
            if missing_tags:
                self.critical()
                self.msg += " (expected tag{plural} '{missing_tags}' not found in entity)".format(
                    missing_tags=','.join(missing_tags),
                    plural=plural(self.tags))
                return missing_tags
        return []

    def check_missing_traits(self, traits):
        if not isList(traits):
            raise UnknownError('traits non-list returned. {0}'.format(support_msg_api()))
        if self.traits:
            missing_traits = []
            #traits = [t.lower() for t in traits]
            for trait in self.traits:
                #if trait.lower() not in traits:
                if trait not in traits:
                    missing_traits.append(trait)
            if missing_traits:
                self.critical()
                self.msg += " (expected trait{plural} '{missing_traits}' not found in entity)".format(
                    missing_traits=','.join(missing_traits),
                    plural=plural(self.traits))
                return missing_traits
        return []


if __name__ == '__main__':
    CheckAtlasEntity().main()
