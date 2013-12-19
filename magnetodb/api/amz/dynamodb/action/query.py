# Copyright 2013 Mirantis Inc.
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

from magnetodb.api.amz.dynamodb.action import DynamoDBAction
from magnetodb.api.amz.dynamodb import parser

from magnetodb import storage
from magnetodb.storage import models


class QueryDynamoDBAction(DynamoDBAction):
    schema = {
        "required": [parser.Props.KEY_CONDITIONS,
                     parser.Props.TABLE_NAME],
        "properties": {
            parser.Props.ATTRIBUTES_TO_GET: {
                "type": "array",
                "items": {
                    "type": "string",
                    "pattern": parser.ATTRIBUTE_NAME_PATTERN
                }
            },

            parser.Props.CONSISTENT_READ: {
                "type": "boolean"
            },

            parser.Props.EXCLUSIVE_START_KEY: {
                "type": "object",
                "patternProperties": {
                    parser.ATTRIBUTE_NAME_PATTERN: parser.Types.ITEM_VALUE
                }
            },

            parser.Props.INDEX_NAME: {
                "type": "string",
                "pattern": parser.INDEX_NAME_PATTERN
            },

            parser.Props.KEY_CONDITIONS: {
                "type": "object",
                "patternProperties": {
                    parser.ATTRIBUTE_NAME_PATTERN: {
                        "type": "object",
                        "properties": {
                            parser.Props.ATTRIBUTE_VALUE_LIST: {
                                "type": "array",
                                "items": parser.ITEM_VALUE
                            },
                            parser.Props.COMPARISON_OPERATOR: (
                                parser.Types.COMPARISON_OPERATOR
                            )
                        }
                    }
                }
            },

            parser.Props.RETURN_CONSUMED_CAPACITY: (
                parser.Types.RETURN_CONSUMED_CAPACITY
            ),

            parser.Props.SCAN_INDEX_FORWARD: {
                "type": "boolean"
            },

            parser.Props.SELECT: parser.Types.SELECT,

            parser.Props.TABLE_NAME: parser.Types.TABLE_NAME
        }
    }

    def __call__(self):
        table_name = self.action_params.get(parser.Props.TABLE_NAME, None)

        # get attributes_to_get
        attributes_to_get = self.action_params.get(
            parser.Props.ATTRIBUTES_TO_GET, None
        )

        if attributes_to_get is not None:
            attributes_to_get = frozenset(attributes_to_get)

        # parse exclusive_start_key_attributes
        exclusive_start_key_attributes = self.action_params.get(
            parser.Props.EXCLUSIVE_START_KEY, None
        )
        if exclusive_start_key_attributes is not None:
            exclusive_start_key_attributes = (
                parser.Parser.parse_item_attributes(
                    exclusive_start_key_attributes
                )
            )

        #index_name = self.action_params.get(parser.Props.INDEX_NAME, None)

        key_conditions = self.action_params.get(parser.Props.KEY_CONDITIONS,
                                                None)
        if key_conditions is not None:
            key_conditions = parser.Parser.parse_attribute_conditions(
                key_conditions
            )

        # TODO(dukhlov):
        # it would be nice to validate given table_name, key_attributes and
        # attributes_to_get  to schema expectation

        consistent_read = self.action_params.get(
            parser.Props.CONSISTENT_READ, False
        )

        limit = self.action_params.get(parser.Props.LIMIT, None)

        return_consumed_capacity = self.action_params.get(
            parser.Props.RETURN_CONSUMED_CAPACITY,
            parser.Values.RETURN_CONSUMED_CAPACITY_NONE
        )

        order_asc = self.action_params.get(
            parser.Props.SCAN_INDEX_FORWARD, None
        )

        order_type = (
            None if order_asc is None else
            models.ORDER_TYPE_ASC if order_asc else
            models.ORDER_TYPE_DESC
        )

        # format conditions to get item
        indexed_condition_map = {
            name: models.IndexedCondition.eq(value)
            for name, value in key_conditions.iteritems()
        }

        # get item
        result = storage.select_item(
            self.context, table_name, indexed_condition_map,
            attributes_to_get=attributes_to_get, limit=limit,
            consistent=consistent_read, order_type=order_type)

        assert len(result) == 1

        # format response
        response = {
            parser.Props.ITEM: parser.Parser.format_item_attributes(result[0])
        }

        if (return_consumed_capacity !=
                parser.Values.RETURN_CONSUMED_CAPACITY_NONE):
            response[parser.Props.CONSUMED_CAPACITY] = (
                parser.Parser.format_consumed_capacity(
                    return_consumed_capacity, None
                )
            )

        return response
