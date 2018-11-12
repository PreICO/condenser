import * as steem from '@steemit/steem-js';

steem.config.set('address_prefix', 'ESH');

let chain_id = '';
for (let i = 0; i < 32; i++) chain_id += '00';

module.exports = {
    address_prefix: 'ESH',
    expire_in_secs: 15,
    chain_id,
};
