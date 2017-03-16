"""
Basic CLI to create the knesset-data datapackages

Simple interface to the relevant classes that do the actual work
"""
from knesset_datapackage.root import RootDatapackage
import os
import logging
import argparse
import zipfile
from .utils import setup_logging, setup_datapath


def make_datapackage():
    parser = argparse.ArgumentParser(description='Make a datapackage containing all Knesset data')
    parser.add_argument('--days', type=int, default=5, help='generate data for last DAYS days where relevant (default is last 5 days)')
    parser.add_argument('--force', action="store_true", help='force to continue, ignoring errors / warnings')
    parser.add_argument('--include', nargs="*", type=str, help="include only datapackages / resources that start with the given string/s")
    parser.add_argument('--exclude', nargs="*", type=str, help="exclude datapackages / resources that start with the given string/s")
    parser.add_argument('--committee-id', nargs="*", type=int, help="only make data for the given committee ids")
    parser.add_argument('--debug', action="store_true", help="provide more information and debug details")
    parser.add_argument('--http-proxy', type=str, help='url to SOCKS http proxy')
    parser.add_argument('--zip', action="store_true", help="create the datapackage in a zip file")
    parser.add_argument('--all-committees', action="store_true", help="committees resource: fetch all committees, including historical")
    parser.add_argument('--main-committees', action="store_true", help="committees resource: fetch only the active main committees")
    parser.add_argument('--member-id', nargs="*", type=int, help="members resource: fetch only the given member id/s")
    parser.add_argument('--committee-meeting-id', nargs="*", type=int, help="only make data for given committee meeting ids")
    parser.add_argument('--skip-exceptions', action="store_true", help="try to skip over exceptions as much as possible. "
                                                                       "errors will be written in datapackage descriptor "
                                                                       "or inside the relevant data/csv file")
    parser.add_argument('--dry-run', action="store_true", help="skip the actual fetching and saving of data")

    args = parser.parse_args()

    setup_logging(debug=args.debug)
    logger = logging.getLogger()

    data_root = setup_datapath()

    datapackage_root = os.path.join(data_root, 'datapackage')

    logger.info("Generating data for the last {} days".format(args.days))
    logger.info("Datapackage will be written in directory {}".format(datapackage_root))

    if not os.path.exists(datapackage_root):
        os.mkdir(datapackage_root)
    elif len(os.listdir(datapackage_root)) > 0 and not args.force:
        raise Exception('datapackage directory must be empty')

    file_handler = logging.FileHandler(os.path.join(datapackage_root, "datapackage.log"))
    file_handler.setFormatter(logging.Formatter("%(name)s:%(lineno)d\t%(levelname)s\t%(message)s"))
    file_handler.setLevel(logging.INFO)
    logging.root.addHandler(file_handler)

    proxies = {proxy_type: proxy_url for proxy_type, proxy_url in {
        'http': args.http_proxy
    }.iteritems() if proxy_url}

    if len(proxies) > 0:
        logger.info('using proxies: {}'.format(proxies))

    datapackage = RootDatapackage(datapackage_root)
    datapackage.make(days=args.days,
                     force=args.force,
                     exclude=args.exclude,
                     include=args.include,
                     committee_ids=args.committee_id,
                     debug=args.debug,
                     proxies=proxies,
                     member_ids=args.member_id,
                     committee_meeting_ids=args.committee_meeting_id,
                     skip_exceptions=args.skip_exceptions,
                     dry_run=args.dry_run)

    if args.zip:
        logger.info('creating datapackage.zip')
        datapackage.save_to_zip(os.path.join(data_root, "datapackage.zip"), data_root)

    logger.info('GREAT SUCCESS!')
