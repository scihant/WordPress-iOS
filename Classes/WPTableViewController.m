//
//  WPTableViewController.m
//  WordPress
//
//  Created by Brad Angelcyk on 5/22/12.
//  Copyright (c) 2012 WordPress. All rights reserved.
//

#import "WPTableViewController.h"
#import "WPTableViewControllerSubclass.h"
#import "EGORefreshTableHeaderView.h" 
#import "WordPressAppDelegate.h"
#import "EditSiteViewController.h"
#import "ReachabilityUtils.h"
#import "WPWebViewController.h"

NSTimeInterval const WPTableViewControllerRefreshTimeout = 300; // 5 minutes

@interface WPTableViewController () <EGORefreshTableHeaderDelegate>

@property (nonatomic, strong) NSFetchedResultsController *resultsController;
@property (nonatomic) BOOL swipeActionsEnabled;
@property (nonatomic, strong, readonly) UIView *swipeView;
@property (nonatomic, strong) UITableViewCell *swipeCell;
@property (nonatomic, strong) NSIndexPath *firstVisibleIndexPathBeforeDisappear;

- (void)simulatePullToRefresh;
- (void)enableSwipeGestureRecognizer;
- (void)disableSwipeGestureRecognizer;
- (void)swipe:(UISwipeGestureRecognizer *)recognizer direction:(UISwipeGestureRecognizerDirection)direction;
- (void)swipeLeft:(UISwipeGestureRecognizer *)recognizer;
- (void)swipeRight:(UISwipeGestureRecognizer *)recognizer;
- (void)dismissModal:(id)sender;

@end

@implementation WPTableViewController {
    EGORefreshTableHeaderView *_refreshHeaderView;
    NSIndexPath *_indexPathSelectedBeforeUpdates;
    NSIndexPath *_indexPathSelectedAfterUpdates;
    UISwipeGestureRecognizer *_leftSwipeGestureRecognizer;
    UISwipeGestureRecognizer *_rightSwipeGestureRecognizer;
    UISwipeGestureRecognizerDirection _swipeDirection;
    BOOL _animatingRemovalOfModerationSwipeView;
    BOOL didPromptForCredentials;
}

@synthesize blog = _blog;
@synthesize resultsController = _resultsController;
@synthesize swipeActionsEnabled = _swipeActionsEnabled;
@synthesize swipeView = _swipeView;
@synthesize swipeCell = _swipeCell;
@synthesize firstVisibleIndexPathBeforeDisappear;

- (void)dealloc
{
    _resultsController.delegate = nil;
}

- (id)initWithBlog:(Blog *)blog {
    if (self) {
        _blog = blog;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    if (_refreshHeaderView == nil) {
		_refreshHeaderView = [[EGORefreshTableHeaderView alloc] initWithFrame:CGRectMake(0.0f, 0.0f - self.tableView.bounds.size.height, self.view.frame.size.width, self.tableView.bounds.size.height)];
		_refreshHeaderView.delegate = self;
		[self.tableView addSubview:_refreshHeaderView];
	}

	
	//  update the last update date
	[_refreshHeaderView refreshLastUpdatedDate];

    self.tableView.allowsSelectionDuringEditing = YES;
    self.tableView.backgroundColor = TABLE_VIEW_BACKGROUND_COLOR;
    self.tableView.separatorColor = [UIColor colorWithRed:204.0f/255.0f green:204.0f/255.0f blue:204.0f/255.0f alpha:1.0f];
    
    if (self.swipeActionsEnabled) {
        [self enableSwipeGestureRecognizer];
    }
}

- (void)viewDidUnload
{
    [super viewDidUnload];

     _refreshHeaderView = nil;
    
    if (self.swipeActionsEnabled) {
        [self disableSwipeGestureRecognizer];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Scroll to the selected row if the view was restored after a memory warning.
    if (IS_IPHONE && self.firstVisibleIndexPathBeforeDisappear && [[self.resultsController sections] count] > 0) {
        [self.tableView scrollToRowAtIndexPath:self.firstVisibleIndexPathBeforeDisappear atScrollPosition:UITableViewScrollPositionTop animated:NO];
        self.firstVisibleIndexPathBeforeDisappear = nil;
    }
}

- (void)viewDidAppear:(BOOL)animated {
    WordPressAppDelegate *appDelegate = [WordPressAppDelegate sharedWordPressApplicationDelegate];
    if( appDelegate.connectionAvailable == NO ) return; //do not start auto-synch if connection is down

    NSDate *lastSynced = [self lastSyncDate];
    if (lastSynced == nil || ABS([lastSynced timeIntervalSinceNow]) > WPTableViewControllerRefreshTimeout) {
        // If table is at the original scroll position, simulate a pull to refresh
        if (self.tableView.contentOffset.y == 0) {
            [self simulatePullToRefresh];
        } else {
        // Otherwise, just update in the background
            [self syncItemsWithUserInteraction:NO];
        }
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (IS_IPHONE) {
        NSArray *visibleRows = [self.tableView indexPathsForVisibleRows];
        if ([visibleRows count] > 0) {
            self.firstVisibleIndexPathBeforeDisappear = [visibleRows objectAtIndex:0];
        }
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return [super shouldAutorotateToInterfaceOrientation:interfaceOrientation];
}


- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [self removeSwipeView:NO];
    [super setEditing:editing animated:animated];
    _refreshHeaderView.hidden = editing;
}

#pragma mark - Property accessors

- (void)setBlog:(Blog *)blog {
    if (_blog == blog) 
        return;

    _blog = blog;

    self.resultsController = nil;
    [self.tableView reloadData];
    WordPressAppDelegate *appDelegate = [WordPressAppDelegate sharedWordPressApplicationDelegate];
    if ( appDelegate.connectionAvailable == YES && [self.resultsController.fetchedObjects count] == 0 && ![self isSyncing] ) {
        [self simulatePullToRefresh];
    }
}

- (void)setSwipeActionsEnabled:(BOOL)swipeActionsEnabled {
    if (swipeActionsEnabled == _swipeActionsEnabled)
        return;

    _swipeActionsEnabled = swipeActionsEnabled;
    if (self.isViewLoaded) {
        if (_swipeActionsEnabled) {
            [self enableSwipeGestureRecognizer];
        } else {
            [self disableSwipeGestureRecognizer];
        }
    }
}

- (BOOL)swipeActionsEnabled {
    return _swipeActionsEnabled && !self.editing;
}

- (UIView *)swipeView {
    if (_swipeView) {
        return _swipeView;
    }

    _swipeView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, kCellHeight)];
    _swipeView.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"background.png"]];
    
    UIImage *shadow = [[UIImage imageNamed:@"inner-shadow.png"] stretchableImageWithLeftCapWidth:0 topCapHeight:0];
    UIImageView *shadowImageView = [[UIImageView alloc] initWithFrame:_swipeView.frame];
    shadowImageView.alpha = 0.5;
    shadowImageView.image = shadow;
    shadowImageView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    [_swipeView insertSubview:shadowImageView atIndex:0];  

    return _swipeView;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [[self.resultsController sections] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    id <NSFetchedResultsSectionInfo> sectionInfo = [[self.resultsController sections] objectAtIndex:section];
    return [sectionInfo name];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    id <NSFetchedResultsSectionInfo> sectionInfo = nil;
    sectionInfo = [[self.resultsController sections] objectAtIndex:section];
    return [sectionInfo numberOfObjects];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self newCell];

    if (IS_IPAD || self.tableView.isEditing) {
		cell.accessoryType = UITableViewCellAccessoryNone;
	} else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    
    [self configureCell:cell atIndexPath:indexPath];

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return kCellHeight;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return kSectionHeaderHight;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (NSIndexPath *)tableView:(UITableView *)theTableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (!self.editing) {
        [self removeSwipeView:YES];
    }
    return indexPath;
}

#pragma mark -
#pragma mark Fetched results controller

- (NSFetchedResultsController *)resultsController {
    if (_resultsController != nil) {
        return _resultsController;
    }

    NSManagedObjectContext *moc = self.blog.managedObjectContext;    
    _resultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:[self fetchRequest]
                                                             managedObjectContext:moc
                                                               sectionNameKeyPath:[self sectionNameKeyPath]
                                                                        cacheName:[NSString stringWithFormat:@"%@-%@", [self entityName], [self.blog objectID]]];
    _resultsController.delegate = self;
        
    NSError *error = nil;
    if (![_resultsController performFetch:&error]) {
        WPFLog(@"%@ couldn't fetch %@: %@", self, [self entityName], [error localizedDescription]);
        _resultsController = nil;
    }
    
    return _resultsController;
}

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller {
    _indexPathSelectedBeforeUpdates = [self.tableView indexPathForSelectedRow];
    [self.tableView beginUpdates];
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    [self.tableView endUpdates];
    if (_indexPathSelectedAfterUpdates) {
        [self.tableView selectRowAtIndexPath:_indexPathSelectedAfterUpdates animated:NO scrollPosition:UITableViewScrollPositionNone];

        _indexPathSelectedBeforeUpdates = nil;
        _indexPathSelectedAfterUpdates = nil;
    }
}

- (void)controller:(NSFetchedResultsController *)controller
   didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath
     forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath {

    if (NSFetchedResultsChangeUpdate == type && newIndexPath && ![newIndexPath isEqual:indexPath]) {
        // Seriously, Apple?
        // http://developer.apple.com/library/ios/#releasenotes/iPhone/NSFetchedResultsChangeMoveReportedAsNSFetchedResultsChangeUpdate/_index.html
        type = NSFetchedResultsChangeMove;
    }
    if (newIndexPath == nil) {
        // It seems in some cases newIndexPath can be nil for updates
        newIndexPath = indexPath;
    }

    switch(type) {            
        case NSFetchedResultsChangeInsert:
            [self.tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:newIndexPath] withRowAnimation:UITableViewRowAnimationFade];
            break;
            
        case NSFetchedResultsChangeDelete:
            [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
            if ([_indexPathSelectedBeforeUpdates isEqual:indexPath]) {
                [self.panelNavigationController popToViewController:self animated:YES];
            }
            break;
            
        case NSFetchedResultsChangeUpdate:
            [self configureCell:[self.tableView cellForRowAtIndexPath:indexPath] atIndexPath:newIndexPath];
            break;
            
        case NSFetchedResultsChangeMove:
            [self.tableView deleteRowsAtIndexPaths:[NSArray
                                                       arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
            [self.tableView insertRowsAtIndexPaths:[NSArray
                                                       arrayWithObject:newIndexPath] withRowAnimation:UITableViewRowAnimationFade];
            if ([_indexPathSelectedBeforeUpdates isEqual:indexPath] && _indexPathSelectedAfterUpdates == nil) {
                _indexPathSelectedAfterUpdates = newIndexPath;
            }
            break;
    }    
}

- (void)controller:(NSFetchedResultsController *)controller didChangeSection:(id )sectionInfo atIndex:(NSUInteger)sectionIndex forChangeType:(NSFetchedResultsChangeType)type {
    switch(type) {
        case NSFetchedResultsChangeInsert:
            [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
            break;
            
        case NSFetchedResultsChangeDelete:
            [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
            break;
    }
}

#pragma mark - EGORefreshTableHeaderDelegate Methods

- (void)egoRefreshTableHeaderDidTriggerRefresh:(EGORefreshTableHeaderView *)view{
	[self syncItemsWithUserInteraction:YES];
}

- (BOOL)egoRefreshTableHeaderDataSourceIsLoading:(EGORefreshTableHeaderView *)view{
	return [self isSyncing]; // should return if data source model is reloading
}

- (NSDate*)egoRefreshTableHeaderDataSourceLastUpdated:(EGORefreshTableHeaderView *)view{
	return [self lastSyncDate]; // should return date data source was last changed
}

#pragma mark -
#pragma mark UIScrollViewDelegate Methods

- (void)scrollViewDidScroll:(UIScrollView *)scrollView{
	if (!self.editing)
        [_refreshHeaderView egoRefreshScrollViewDidScroll:scrollView];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate{
	if (!self.editing)
		[_refreshHeaderView egoRefreshScrollViewDidEndDragging:scrollView];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (self.panelNavigationController) {
        [self.panelNavigationController viewControllerWantsToBeFullyVisible:self];
    }
    if (self.swipeActionsEnabled) {
        [self removeSwipeView:YES];
    }
}


#pragma mark -
#pragma mark UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex { 
	switch(buttonIndex) {
		case 0: {
            HelpViewController *helpViewController = [[HelpViewController alloc] init];
            helpViewController.isBlogSetup = YES;
            helpViewController.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(dismissModal:)];
            // Probably should be modal
            UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:helpViewController];
            if (IS_IPAD) {
                navController.modalPresentationStyle = UIModalPresentationFormSheet;
                navController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
            }
            [self.panelNavigationController presentModalViewController:navController animated:YES];

			break;
		}
		case 1:
            if (alertView.tag == 30){
                NSString *path = nil;
                NSError *error = NULL;
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"http\\S+writing.php" options:NSRegularExpressionCaseInsensitive error:&error];
                NSString *msg = [alertView message];
                NSRange rng = [regex rangeOfFirstMatchInString:msg options:0 range:NSMakeRange(0, [msg length])];
                
                if (rng.location == NSNotFound) {
                    path = self.blog.url;
                    if (![path hasPrefix:@"http"]) {
                        path = [NSString stringWithFormat:@"http://%@", path];
                    } else if ([self.blog isWPcom] && [path rangeOfString:@"wordpress.com"].location == NSNotFound) {
                        path = [self.blog.xmlrpc stringByReplacingOccurrencesOfString:@"xmlrpc.php" withString:@""];
                    }
                    path = [path stringByReplacingOccurrencesOfString:@"xmlrpc.php" withString:@""];
                    path = [path stringByAppendingFormat:@"/wp-admin/options-writing.php"];
                    
                } else {
                    path = [msg substringWithRange:rng];
                }
                
                WPWebViewController *webViewController;
                if ( IS_IPAD ) {
                    webViewController = [[WPWebViewController alloc] initWithNibName:@"WPWebViewController-iPad" bundle:nil];
                } else {
                    webViewController = [[WPWebViewController alloc] initWithNibName:@"WPWebViewController" bundle:nil];
                }
                webViewController.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(dismissModal:)];
                [webViewController setUrl:[NSURL URLWithString:path]];
                [webViewController setUsername:self.blog.username];
                [webViewController setPassword:[self.blog fetchPassword]];
                [webViewController setWpLoginURL:[NSURL URLWithString:self.blog.loginURL]];
                webViewController.shouldScrollToBottom = YES;
                // Probably should be modal.
                UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:webViewController];
                if (IS_IPAD) {
                    navController.modalPresentationStyle = UIModalPresentationFormSheet;
                    navController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
                }
                [self.panelNavigationController presentModalViewController:navController animated:YES];
            }
			break;
		default:
			break;
	}
}

#pragma mark - Private Methods

- (void)dismissModal:(id)sender {
    [self dismissModalViewControllerAnimated:YES];
}

- (void)simulatePullToRefresh {
    if(!_refreshHeaderView) return;
    
    CGPoint offset = self.tableView.contentOffset;
    offset.y = - 65.0f;
    [self.tableView setContentOffset:offset];
    [_refreshHeaderView egoRefreshScrollViewDidEndDragging:self.tableView];
}

- (void)syncItemsWithUserInteraction:(BOOL)userInteraction {
    if (![ReachabilityUtils isInternetReachable]) {
        [ReachabilityUtils showAlertNoInternetConnection];
        [_refreshHeaderView performSelector:@selector(egoRefreshScrollViewDataSourceDidFinishedLoading:) withObject:self.tableView afterDelay:0.1];
        return;
    }
    
    [self syncItemsWithUserInteraction:userInteraction success:^{
        [_refreshHeaderView egoRefreshScrollViewDataSourceDidFinishedLoading:self.tableView];
    } failure:^(NSError *error) {
        [_refreshHeaderView egoRefreshScrollViewDataSourceDidFinishedLoading:self.tableView];
        if (error.code == 405) {
            // FIXME: this looks like "Enable XML-RPC" which is going away
            // If it's not, don't rely on whatever the error message is if we are showing custom actions like 'Enable Now'
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Couldn't sync", @"")
                                                                message:[error localizedDescription]
                                                               delegate:self
                                                      cancelButtonTitle:NSLocalizedString(@"Need Help?", @"")
                                                      otherButtonTitles:NSLocalizedString(@"Enable Now", @""), nil];
            
            alertView.tag = 30;
            [alertView show];
            
        } else {
            [WPError showAlertWithError:error title:NSLocalizedString(@"Couldn't sync", @"")];
        }
        if (error.code == 403 && !didPromptForCredentials) {
            // bad login/pass combination
            EditSiteViewController *controller = [[EditSiteViewController alloc] initWithNibName:nil bundle:nil];
            controller.blog = self.blog;
            controller.isCancellable = YES;
            UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller];
            
            if(IS_IPAD == YES) {
                navController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
                navController.modalPresentationStyle = UIModalPresentationFormSheet;
            }
            
            [self.panelNavigationController presentModalViewController:navController animated:YES];
            
            didPromptForCredentials = YES;
        }
    }];
}

#pragma mark - Swipe gestures

- (void)enableSwipeGestureRecognizer {
    [self disableSwipeGestureRecognizer]; // Disable any existing gesturerecognizers before initing new ones to avoid leaks.
    
    _leftSwipeGestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeft:)];
    _leftSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionLeft;
    [self.tableView addGestureRecognizer:_leftSwipeGestureRecognizer];

    _rightSwipeGestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRight:)];
    _rightSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionRight;
    [self.tableView addGestureRecognizer:_rightSwipeGestureRecognizer];
}

- (void)disableSwipeGestureRecognizer {
    if (_leftSwipeGestureRecognizer) {
        [self.tableView removeGestureRecognizer:_leftSwipeGestureRecognizer];
        _leftSwipeGestureRecognizer = nil;
    }

    if (_rightSwipeGestureRecognizer) {
        [self.tableView removeGestureRecognizer:_rightSwipeGestureRecognizer];
        _rightSwipeGestureRecognizer = nil;
    }
}

- (void)removeSwipeView:(BOOL)animated {
    if (!self.swipeActionsEnabled || !_swipeCell || (self.swipeCell.frame.origin.x == 0 && self.swipeView.superview == nil)) return;
    
    if (animated)
    {
        _animatingRemovalOfModerationSwipeView = YES;
        [UIView animateWithDuration:0.2
                         animations:^{
                             if (_swipeDirection == UISwipeGestureRecognizerDirectionRight)
                             {
                                 self.swipeView.frame = CGRectMake(-self.swipeView.frame.size.width + 5.0,self.swipeView.frame.origin.y, self.swipeView.frame.size.width, self.swipeView.frame.size.height);
                                 self.swipeCell.frame = CGRectMake(5.0, self.swipeCell.frame.origin.y, self.swipeCell.frame.size.width, self.swipeCell.frame.size.height);
                             }
                             else
                             {
                                 self.swipeView.frame = CGRectMake(self.swipeView.frame.size.width - 5.0,self.swipeView.frame.origin.y,self.swipeView.frame.size.width, self.swipeView.frame.size.height);
                                 self.swipeCell.frame = CGRectMake(-5.0, self.swipeCell.frame.origin.y, self.swipeCell.frame.size.width, self.swipeCell.frame.size.height);
                             }
                         }
                         completion:^(BOOL finished) {
                             [UIView animateWithDuration:0.1
                                              animations:^{
                                                  if (_swipeDirection == UISwipeGestureRecognizerDirectionRight)
                                                  {
                                                      self.swipeView.frame = CGRectMake(-self.swipeView.frame.size.width + 10.0,self.swipeView.frame.origin.y,self.swipeView.frame.size.width, self.swipeView.frame.size.height);
                                                      self.swipeCell.frame = CGRectMake(10.0, self.swipeCell.frame.origin.y, self.swipeCell.frame.size.width, self.swipeCell.frame.size.height);
                                                  }
                                                  else
                                                  {
                                                      self.swipeView.frame = CGRectMake(self.swipeView.frame.size.width - 10.0,self.swipeView.frame.origin.y,self.swipeView.frame.size.width, self.swipeView.frame.size.height);
                                                      self.swipeCell.frame = CGRectMake(-10.0, self.swipeCell.frame.origin.y, self.swipeCell.frame.size.width, self.swipeCell.frame.size.height);
                                                  }
                                              } completion:^(BOOL finished) {
                                                  [UIView animateWithDuration:0.1
                                                                   animations:^{
                                                                       if (_swipeDirection == UISwipeGestureRecognizerDirectionRight)
                                                                       {
                                                                           self.swipeView.frame = CGRectMake(-self.swipeView.frame.size.width ,self.swipeView.frame.origin.y,self.swipeView.frame.size.width, self.swipeView.frame.size.height);
                                                                           self.swipeCell.frame = CGRectMake(0, self.swipeCell.frame.origin.y, self.swipeCell.frame.size.width, self.swipeCell.frame.size.height);
                                                                       }
                                                                       else
                                                                       {
                                                                           self.swipeView.frame = CGRectMake(self.swipeView.frame.size.width ,self.swipeView.frame.origin.y,self.swipeView.frame.size.width, self.swipeView.frame.size.height);
                                                                           self.swipeCell.frame = CGRectMake(0, self.swipeCell.frame.origin.y, self.swipeCell.frame.size.width, self.swipeCell.frame.size.height);
                                                                       }
                                                                   }
                                                                   completion:^(BOOL finished) {
                                                                       _animatingRemovalOfModerationSwipeView = NO;
                                                                       self.swipeCell = nil;
                                                                       [_swipeView removeFromSuperview];
                                                                        _swipeView = nil;
                                                                   }];
                                              }];
                         }];
    }
    else
    {
        [self.swipeView removeFromSuperview];
         _swipeView = nil;
        self.swipeCell.frame = CGRectMake(0,self.swipeCell.frame.origin.y,self.swipeCell.frame.size.width, self.swipeCell.frame.size.height);
        self.swipeCell = nil;
    }
}

- (void)swipe:(UISwipeGestureRecognizer *)recognizer direction:(UISwipeGestureRecognizerDirection)direction
{
    if (!self.swipeActionsEnabled) {
        return;
    }
    if (recognizer && recognizer.state == UIGestureRecognizerStateEnded)
    {
        if (_animatingRemovalOfModerationSwipeView) return;
        
        CGPoint location = [recognizer locationInView:self.tableView];
        NSIndexPath* indexPath = [self.tableView indexPathForRowAtPoint:location];
        UITableViewCell* cell = [self.tableView cellForRowAtIndexPath:indexPath];
        
        if (cell.frame.origin.x != 0)
        {
            [self removeSwipeView:YES];
            return;
        }
        [self removeSwipeView:NO];
        
        if (cell != self.swipeCell)
        {
            [self configureSwipeView:self.swipeView forIndexPath:indexPath];
            
            [self.tableView addSubview:self.swipeView];
            self.swipeCell = cell;
            CGRect cellFrame = cell.frame;
            _swipeDirection = direction;
            self.swipeView.frame = CGRectMake(direction == UISwipeGestureRecognizerDirectionRight ? -cellFrame.size.width : cellFrame.size.width, cellFrame.origin.y, cellFrame.size.width, cellFrame.size.height);
            
            [UIView animateWithDuration:0.2 animations:^{
                self.swipeView.frame = CGRectMake(0, cellFrame.origin.y, cellFrame.size.width, cellFrame.size.height);
                cell.frame = CGRectMake(direction == UISwipeGestureRecognizerDirectionRight ? cellFrame.size.width : -cellFrame.size.width, cellFrame.origin.y, cellFrame.size.width, cellFrame.size.height);
            }];
        }
    }
}

- (void)swipeLeft:(UISwipeGestureRecognizer *)recognizer
{
    [self swipe:recognizer direction:UISwipeGestureRecognizerDirectionLeft];
}

- (void)swipeRight:(UISwipeGestureRecognizer *)recognizer
{
    [self swipe:recognizer direction:UISwipeGestureRecognizerDirectionRight];
}


#pragma mark - Subclass methods

#define AssertSubclassMethod() @throw [NSException exceptionWithName:NSInternalInconsistencyException\
                                                    reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)] \
                                                    userInfo:nil]

- (NSString *)entityName {
    AssertSubclassMethod();
}

- (NSDate *)lastSyncDate {
    AssertSubclassMethod();
}

- (NSFetchRequest *)fetchRequest {
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    [fetchRequest setEntity:[NSEntityDescription entityForName:[self entityName] inManagedObjectContext:self.blog.managedObjectContext]];
    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"blog == %@", self.blog]];

    return fetchRequest;
}

- (NSString *)sectionNameKeyPath {
    return nil;
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    AssertSubclassMethod();
}

- (void)syncItemsWithUserInteraction:(BOOL)userInteraction success:(void (^)())success failure:(void (^)(NSError *))failure {
    AssertSubclassMethod();
}

- (BOOL)isSyncing {
	AssertSubclassMethod();
}

- (UITableViewCell *)newCell {
    // To comply with apple ownership and naming conventions, returned cell should have a retain count > 0, so retain the dequeued cell.
    NSString *cellIdentifier = [NSString stringWithFormat:@"_WPTable_%@_Cell", [self entityName]];
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }
    return cell;
}

- (BOOL)hasMoreContent {
    return NO;
}

- (void)loadMoreContent {
}

@end
