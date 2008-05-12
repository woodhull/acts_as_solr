# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

class Solr::Request::MoreLikeThis < Solr::Request::Standard

  VALID_PARAMS.replace(VALID_PARAMS + [])

  def initialize(params)
    @alternate_query = params.delete(:alternate_query)
    @sort_values = params.delete(:sort)

    super

    @query_type = "mlt"
  end

  def to_hash
    hash = super
    return hash
  end

end