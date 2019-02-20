#https://docs.microsoft.com/en-us/dotnet/api/system.drawing?view=netframework-4.7.2

# Create a Point object using integers for X, and Y coordinates
[System.Drawing.Point]::new(1,1)

# https://docs.microsoft.com/en-us/dotnet/api/system.drawing.drawing2d.graphicspath?view=netframework-4.7.2
# https://docs.microsoft.com/en-us/dotnet/api/system.drawing.drawing2d.pathpointtype?view=netframework-4.7.2
# Create a GraphicsPath using a collection of points.
# The second array defines the point type. 1 is just a line.
$Points = @(
  [System.Drawing.Point]::new(3,0)
  [System.Drawing.Point]::new(0,-3)
  [System.Drawing.Point]::new(-3,0)
  [System.Drawing.Point]::new(0,3)
)

$GraphicsPath = [System.Drawing.Drawing2D.GraphicsPath]::new($Points, @(1,1,1,1))

#https://docs.microsoft.com/en-us/dotnet/api/system.drawing.region?view=netcore-2.2
# Create a new region from a GraphicsPath
$Region = [System.Drawing.Region]::new($GraphicsPath)