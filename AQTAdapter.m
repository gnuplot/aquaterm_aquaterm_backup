//
//  AQTAdapter.m
//  AquaTerm
//
//  Created by Per Persson on Sat Jul 12 2003.
//  Copyright (c) 2003-2004 AquaTerm. 
//

#import "AQTAdapter.h"
#import "AQTClientManager.h"
#import "AQTPlotBuilder.h"

@implementation AQTAdapter
/*" AQTAdapter is a class that provides an interface to the functionality of AquaTerm.
As such, it bridges the gap between client's procedural calls requesting operations
such as drawing a line or placing a label and the object-oriented graph being built.
The actual assembling of the graph is performed by an instance of class AQTPlotBuilder.

It seemlessly provides a connection to the viewer (AquaTerm.app) without any work on behalf of the client.

It also provides some utility functionality such an indexed colormap, and an optional
error handling callback function for the client.

Event handling of user input is provided through an optional callback function.

#Example: HelloAquaTerm.c
!{
#import <Foundation/Foundation.h>
#import <AquaTerm/AQTAdapter.h>

   int main(void)
   {
      NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
      AQTAdapter *adapter = [[AQTAdapter alloc] init];
      [adapter openPlotWithIndex:1];
      [adapter setPlotSize:NSMakeSize(600,400)];
      [adapter addLabel:@"HelloAquaTerm!" atPoint:NSMakePoint(300, 200) angle:0.0 align:1];
      [adapter renderPlot];
      [adapter release];
      [pool release];
      return 0;
   }
}
!{gcc -ObjC main.c -o aqtex -lobjc -framework AquaTerm -framework Foundation}
!{gcc main.m -o aqtex -framework AquaTerm -framework Foundation}
"*/

/*" This is the designated initalizer, allowing for the default handler (an object vended by AquaTerm via OS X's distributed objects mechanism) to be replaced by a local instance. In most cases #init should be used, which calls #initWithHandler: with a nil argument."*/
-(id)initWithServer:(id)localServer
{
   if(self = [super init]) {
      BOOL serverIsOK = YES;
      _clientManager = [AQTClientManager sharedManager];
      if (localServer) {
         [_clientManager setServer:localServer];
      } else {
         serverIsOK = [_clientManager connectToServer];
      }
      if (!serverIsOK) {
         [self autorelease];
         self = nil;
      }
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(connectionDidDie:)
                                                   name:NSConnectionDidDieNotification
                                                 object:nil];
   }
   return self;
}

/*" Initializes an instance and sets up a connection to the handler object via DO. Launches AquaTerm if necessary. "*/
- (id)init
{
   return [self initWithServer:nil];
}

- (void)release
{
   [_clientManager logMessage:[NSString stringWithFormat:@"adapter rc = %d", [self retainCount]] logLevel:3];
   [super release];
}

- (void)dealloc
{
   [_clientManager logMessage:@"adapter dealloc, terminating connection." logLevel:3];
   [[NSNotificationCenter defaultCenter] removeObserver:self];
   [_clientManager terminateConnection];
   [super dealloc];
}

/*" Optionally set an error handling routine of the form #customErrorHandler(NSString *errMsg) to override default behaviour. "*/
- (void)setErrorHandler:(void (*)(NSString *errMsg))fPtr
{
   [_clientManager setErrorHandler:fPtr];
}

/*" Optionally set an event handling routine of the form #customEventHandler(int index, NSString *event).
The reference number of the plot that generated the event is passed in index and
the structure of the string event is @"type:data1:data2:..."
Currently supported events are:
_{event description}
_{0 NoEvent }
_{1:%{x,y}:%button MouseDownEvent }
_{2:%{x,y}:%key KeyDownEvent } 
_{42:%{x,y}:%key ServerError }
_{43:%{x,y}:%key Error } "*/
- (void)setEventHandler:(void (*)(int32_t index, NSString *event))fPtr
{
   [_clientManager setEventHandler:fPtr];
}

- (void)connectionDidDie:(id)x
{
   // NSLog(@"in --> %@ %s line %d", NSStringFromSelector(_cmd), __FILE__, __LINE__);
   // Make sure we can't access any invalid objects:
   _selectedBuilder = nil;
}

#pragma mark === Control operations ===

/* Creates a new builder instance, adds it to the list of builders and makes it the selected builder. If the referenced builder exists, it is selected and cleared. */
/*" Open up a new plot with internal reference number refNum and make it the target for subsequent commands. If the referenced plot already exists, it is selected and cleared. Disables event handling for previously targeted plot. "*/
- (void)openPlotWithIndex:(int32_t)refNum
{
   _selectedBuilder = [_clientManager newPlotWithIndex:refNum];
}

/*" Get the plot referenced by refNum and make it the target for subsequent commands. If no plot exists for refNum, the currently targeted plot remain unchanged. Disables event handling for previously targeted plot. Returns YES on success. "*/
- (BOOL)selectPlotWithIndex:(int32_t)refNum
{
   BOOL didChangePlot = NO;
   AQTPlotBuilder *tmpBuilder = [_clientManager selectPlotWithIndex:refNum];
   if (tmpBuilder != nil)
   {
      _selectedBuilder = tmpBuilder;
      didChangePlot = YES;
   }
   return didChangePlot;
}

/*" Set the limits of the plot area. Must be set %before any drawing command following an #openPlotWithIndex: or #clearPlot command or behaviour is undefined.  "*/
- (void)setPlotSize:(NSSize)canvasSize
{
   [_selectedBuilder setSize:canvasSize];
}

/*" Set title to appear in window titlebar, also default name when saving. "*/
- (void)setPlotTitle:(NSString *)title
{
   [_selectedBuilder setTitle:title?title:@"Untitled"];
}

/*" Render the current plot in the viewer. "*/
- (void)renderPlot
{
   if(_selectedBuilder)
   {
      [_clientManager renderPlot];
   }
   else
   {
      // Just inform user about what is going on...
      [_clientManager logMessage:@"Warning: No plot selected" logLevel:2];
   }
}

/*" Clears the current plot and resets default values. To keep plot settings, use #eraseRect: instead. "*/
- (void)clearPlot
{
      _selectedBuilder = [_clientManager clearPlot];
}

/*" Closes the current plot but leaves viewer window on screen. Disables event handling. "*/
- (void)closePlot 
{
   [_clientManager closePlot];
   _selectedBuilder = nil;
}

#pragma mark === Event handling ===

/*" Inform AquaTerm whether or not events should be passed from the currently selected plot. Deactivates event passing from any plot previously set to pass events. "*/
- (void)setAcceptingEvents:(BOOL)flag 
{
   [_clientManager setAcceptingEvents:flag]; 
}

/*" Reads the last event logged by the viewer. Will always return NoEvent unless #setAcceptingEvents: is called with a YES argument."*/
- (NSString *)lastEvent
{
   [[NSRunLoop currentRunLoop] runMode:NSConnectionReplyMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
   return [_clientManager lastEvent]; 
}

- (NSString *)waitNextEvent // FIXME: timeout? Hardcoded to 10s
{
 NSString *event;
   BOOL isRunning;
   [self setAcceptingEvents:YES];
   do {
      isRunning = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:10.0]];
      event = [_clientManager lastEvent];
      isRunning = [event isEqualToString:@"0"]?YES:NO;
   } while (isRunning);
   [self setAcceptingEvents:NO];
   return event;
}

#pragma mark === Plotting commands ===

/*" Set a clipping region (rectangular) to apply to all subsequent operations, until changed again by #setClipRect: or #setDefaultClipRect. "*/ 
- (void)setClipRect:(NSRect)clip
{
   [_selectedBuilder setClipRect:clip];
}

/*" Restore clipping region to the deafult (object bounds), i.e. no clipping performed. "*/
- (void)setDefaultClipRect
{
   [_selectedBuilder setDefaultClipRect];
}

/*" Return the number of color entries available in the currently active colormap. "*/
- (int32_t)colormapSize
{
   int32_t size = AQT_COLORMAP_SIZE; // Default size
   if (_selectedBuilder)
   {
      size = [_selectedBuilder colormapSize];
   }
   else
   {
      // Just inform user about what is going on...
      [_clientManager logMessage:@"Warning: No plot selected" logLevel:2];
   }
   return size;
}

/*" Set an RGB entry in the colormap, at the position given by entryIndex. "*/
- (void)setColormapEntry:(int32_t)entryIndex red:(float)r green:(float)g blue:(float)b alpha:(float)a
{
   AQTColor tmpColor;
   tmpColor.red = r;
   tmpColor.green = g;
   tmpColor.blue = b;
   tmpColor.alpha = a;
   [_selectedBuilder setColor:tmpColor forColormapEntry:entryIndex];
}

- (void)setColormapEntry:(int32_t)entryIndex red:(float)r green:(float)g blue:(float)b 
{
   [self setColormapEntry:entryIndex red:r green:g blue:b alpha:1.0];
}


/*" Set an RGB entry in the colormap, at the position given by entryIndex. "*/
- (void)getColormapEntry:(int32_t)entryIndex red:(float *)r green:(float *)g blue:(float *)b alpha:(float *)a
{
   AQTColor tmpColor = [_selectedBuilder colorForColormapEntry:entryIndex];
   *r = tmpColor.red;
   *g = tmpColor.green;
   *b = tmpColor.blue;
   *a = tmpColor.alpha;
}

- (void)getColormapEntry:(int32_t)entryIndex red:(float *)r green:(float *)g blue:(float *)b
{
   float dummyAlpha;
   [self getColormapEntry:entryIndex red:r green:g blue:b alpha:&dummyAlpha];
}


/*" Set the current color, used for all subsequent items, using the color stored at the position given by index in the colormap. "*/
- (void)takeColorFromColormapEntry:(int32_t)index
{
   [_selectedBuilder takeColorFromColormapEntry:index];
}

/*" Set the background color, overriding any previous color, using the color stored at the position given by index in the colormap. "*/
- (void)takeBackgroundColorFromColormapEntry:(int32_t)index
{
   [_selectedBuilder takeBackgroundColorFromColormapEntry:index];
}

/*" Set the current color, used for all subsequent items, using explicit RGB components. "*/
- (void)setColorRed:(float)r green:(float)g blue:(float)b alpha:(float)a
{
   AQTColor newColor = (AQTColor){r, g, b, a};
   [_selectedBuilder setColor:newColor];
}

- (void)setColorRed:(float)r green:(float)g blue:(float)b
{
   [self setColorRed:r green:g blue:b alpha:1.0];
}


/*" Set the background color, overriding any previous color, using explicit RGB components. "*/
- (void)setBackgroundColorRed:(float)r green:(float)g blue:(float)b alpha:(float)a
{
   AQTColor newColor = (AQTColor){r, g, b, a};
   [_selectedBuilder setBackgroundColor:newColor];
}

- (void)setBackgroundColorRed:(float)r green:(float)g blue:(float)b
{
   [self setBackgroundColorRed:r green:g blue:b alpha:1.0];
}


/*" Get current RGB color components by reference. "*/
- (void)getColorRed:(float *)r green:(float *)g blue:(float *)b alpha:(float *)a
{
   AQTColor tmpColor = [_selectedBuilder color];
   *r = tmpColor.red;
   *g = tmpColor.green;
   *b = tmpColor.blue;
   *a = tmpColor.alpha;
}


- (void)getColorRed:(float *)r green:(float *)g blue:(float *)b
{
   AQTColor tmpColor = [_selectedBuilder color];
   *r = tmpColor.red;
   *g = tmpColor.green;
   *b = tmpColor.blue;
}

/*" Get background color components by reference. "*/
- (void)getBackgroundColorRed:(float *)r green:(float *)g blue:(float *)b alpha:(float *)a
{
    AQTColor tmpColor = [_selectedBuilder backgroundColor];
    *r = tmpColor.red;
    *g = tmpColor.green;
    *b = tmpColor.blue;
    *a = tmpColor.alpha;
}


- (void)getBackgroundColorRed:(float *)r green:(float *)g blue:(float *)b
{
   float dummyAlpha;
   [self getBackgroundColorRed:r green:g blue:b alpha:&dummyAlpha];
}


/*" Set the font to be used. Applies to all future operations. Default is Times-Roman."*/
- (void)setFontname:(NSString *)newFontname
{
   [_selectedBuilder setFontname:newFontname];
}

/*" Set the font size in points. Applies to all future operations. Default is 14pt. "*/
- (void)setFontsize:(float)newFontsize
{
   [_selectedBuilder setFontsize:newFontsize];
}

/*" Add text at coordinate given by pos, rotated by angle degrees and aligned vertically and horisontally (with respect to pos and rotation) according to align. Horizontal and vertical align may be combined by an OR operation, e.g. (AQTAlignCenter | AQTAlignMiddle).
_{HorizontalAlign Description}
_{AQTAlignLeft LeftAligned}
_{AQTAlignCenter Centered}
_{AQTAlignRight RightAligned}
_{VerticalAlign -}
_{AQTAlignMiddle ApproxCenter}
_{AQTAlignBaseline Normal}
_{AQTAlignBottom BottomBoundsOfTHISString}
_{AQTAlignTop TopBoundsOfTHISString}
By specifying #shearAngle the text may be sheared in order to appear correctly in e.g. 3D plot labels. 
The text can be either an NSString or an NSAttributedString. By using NSAttributedString a subset of the attributes defined in AppKit may be used to format the string beyond the fontface ans size. The currently supported attributes are
_{Attribute value}
_{@"NSSuperScript" raise-level}
_{@"NSUnderline" 0or1}
"*/
- (void)addLabel:(id)text atPoint:(NSPoint)pos angle:(float)angle shearAngle:(float)shearAngle align:(int32_t)just
{
   [_selectedBuilder addLabel:text position:pos angle:angle shearAngle:shearAngle justification:just];
}

/*" Same as #addLabel:atPoint:angle:shearAngle:align: except that shearAngle defaults to 0."*/
- (void)addLabel:(id)text atPoint:(NSPoint)pos angle:(float)angle align:(int32_t)just
{
   [_selectedBuilder addLabel:text position:pos angle:angle shearAngle:0.0 justification:just];
}

/*" Convenience form of #addLabel:atPoint:angle:shearAngle:align: for horizontal, left and baseline aligned text."*/
- (void)addLabel:(id)text atPoint:(NSPoint)pos
{
   [_selectedBuilder addLabel:text position:pos angle:0.0 shearAngle:0.0 justification:(AQTAlignLeft | AQTAlignBaseline)];
}



/*" Set the current linewidth (in points), used for all subsequent lines. Any line currently being built by #moveToPoint:/#addLineToPoint will be considered finished since any coalesced sequence of line segments must share the same linewidth.  Default linewidth is 1pt."*/
- (void)setLinewidth:(float)newLinewidth
{
   [_selectedBuilder setLinewidth:newLinewidth];
}

/*" Set the current line style to pattern style, used for all subsequent lines. The linestyle is specified as a pattern, an array of at most 8 float, where even positions correspond to dash-lengths and odd positions correspond to gap-lengths. To produce e.g. a dash-dotted line, use the pattern {4.0, 2.0, 1.0, 2.0}."*/
- (void)setLinestylePattern:(float *)newPattern count:(int32_t)newCount phase:(float)newPhase
{
   [_selectedBuilder setLinestylePattern:newPattern count:newCount phase:newPhase];
}

/*" Set the current line style to solid, used for all subsequent lines. This is the default."*/
- (void)setLinestyleSolid
{
   [_selectedBuilder setLinestyleSolid];
}

/*" Set the current line cap style (in points), used for all subsequent lines. Any line currently being built by #moveToPoint:/#addLineToPoint will be considered finished since any coalesced sequence of line segments must share the same cap style.
_{capStyle Description}
_{AQTButtLineCapStyle ButtLineCapStyle}
_{AQTRoundLineCapStyle RoundLineCapStyle}
_{AQTSquareLineCapStyle SquareLineCapStyle}
Default is RoundLineCapStyle. "*/
- (void)setLineCapStyle:(int32_t)capStyle
{
   [_selectedBuilder setLineCapStyle:capStyle];
}

/*" Moves the current point (in canvas coordinates) in preparation for a new sequence of line segments. "*/
- (void)moveToPoint:(NSPoint)point
{
   [_selectedBuilder moveToPoint:point];
}

/*" Add a line segment from the current point (given by a previous #moveToPoint: or #addLineToPoint). "*/
- (void)addLineToPoint:(NSPoint)point
{
   [_selectedBuilder addLineToPoint:point];
}

/*" Add a sequence of line segments specified by a list of start-, end-, and joinpoint(s) in points. Parameter pc is number of line segments + 1."*/
- (void)addPolylineWithPoints:(NSPoint *)points pointCount:(int32_t)pc
{
   [_selectedBuilder addPolylineWithPoints:points pointCount:pc];
}

- (void)moveToVertexPoint:(NSPoint)point
{
   [_selectedBuilder moveToVertexPoint:point];
}

- (void)addEdgeToVertexPoint:(NSPoint)point
{
   [_selectedBuilder addEdgeToPoint:point];
}

/*" Add a polygon specified by a list of corner points. Number of corners is passed in pc."*/
- (void)addPolygonWithVertexPoints:(NSPoint *)points pointCount:(int32_t)pc
{
   [_selectedBuilder addPolygonWithPoints:points pointCount:pc];
}

/*" Add a filled rectangle. Will attempt to remove any objects that will be covered by aRect."*/
- (void)addFilledRect:(NSRect)aRect
{
   // FIXME: this may be very inefficent, maybe store a AQTClearRect object in the model instead?
   // If the filled rect covers a substantial area, it is worthwile to clear it first.
   if (NSWidth(aRect)*NSHeight(aRect) > 100.0)
   {
      [_clientManager clearPlotRect:aRect];
   }
   [_selectedBuilder addFilledRect:aRect];
}

/*" Remove any objects %completely inside aRect. Does %not force a redraw of the plot."*/
- (void)eraseRect:(NSRect)aRect
{
   // FIXME: Possibly keep a list of rects to be erased and pass them before any append command??
   [_clientManager clearPlotRect:aRect];
}

/*" Set a transformation matrix for images added by #addTransformedImageWithBitmap:size:clipRect:, see NSImage documentation for details. "*/
- (void)setImageTransformM11:(float)m11 m12:(float)m12 m21:(float)m21 m22:(float)m22 tX:(float)tX tY:(float)tY
{
   AQTAffineTransformStruct trans;
   trans.m11 = m11;
   trans.m12 = m12;
   trans.m21 = m21;
   trans.m22 = m22;
   trans.tX = tX;
   trans.tY = tY;
   [_selectedBuilder setImageTransform:trans];
}

/*" Set transformation matrix to unity, i.e. no transform. "*/
- (void)resetImageTransform
{
   AQTAffineTransformStruct trans;
   trans.m11 = 1.0;
   trans.m22 = 1.0;
   [_selectedBuilder setImageTransform:trans];
}

/*" Add a bitmap image of size bitmapSize scaled to fit destBounds, does %not apply transform. Bitmap format is 24bits per pixel in sequence RGBRGB... with 8 bits per color."*/
- (void)addImageWithBitmap:(const void *)bitmap size:(NSSize)bitmapSize bounds:(NSRect)destBounds
{
   [_clientManager clearPlotRect:destBounds];
   [_selectedBuilder addImageWithBitmap:bitmap size:bitmapSize bounds:destBounds];
}

/*" Deprecated, use #addTransformedImageWithBitmap:size: instead. Add a bitmap image of size bitmapSize %honoring transform, transformed image is clipped to destBounds. Bitmap format is 24bits per pixel in sequence RGBRGB...  with 8 bits per color."*/
- (void)addTransformedImageWithBitmap:(const void *)bitmap size:(NSSize)bitmapSize clipRect:(NSRect)destBounds
{
   [_selectedBuilder addTransformedImageWithBitmap:bitmap size:bitmapSize clipRect:destBounds];
}

/*" Add a bitmap image of size bitmapSize %honoring transform, transformed image is clipped to current clipRect. Bitmap format is 24bits per pixel in sequence RGBRGB...  with 8 bits per color."*/
- (void)addTransformedImageWithBitmap:(const void *)bitmap size:(NSSize)bitmapSize
{
   [_selectedBuilder addTransformedImageWithBitmap:bitmap size:bitmapSize];
}

/*******************************************
* Private methods                         *
*******************************************/
- (void)timingTestWithTag:(uint32_t)tag
{
   [_clientManager timingTestWithTag:tag];
}
@end

