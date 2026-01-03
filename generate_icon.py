#!/usr/bin/env python3
"""Generate app icons for Free Ride bike simulation app."""

from PIL import Image, ImageDraw
import os

def create_bike_icon(size):
    """Create a modern fitness activity icon with the given size."""
    # Create image with transparent background
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Modern gradient background (vibrant teal to purple)
    for y in range(size):
        # Gradient from teal to purple
        t = y / size
        r = int(20 + (147 - 20) * t)
        g = int(184 + (51 - 184) * t)
        b = int(166 + (234 - 166) * t)
        draw.rectangle([(0, y), (size, y + 1)], fill=(r, g, b, 255))
    
    # Add rounded corners
    corner_radius = int(size * 0.18)
    # Create a mask for rounded corners
    mask = Image.new('L', (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([(0, 0), (size, size)], corner_radius, fill=255)
    img.putalpha(mask)
    
    # Scale factor for drawing
    s = size / 100
    
    # White color
    white = (255, 255, 255, 255)
    line_width = max(3, int(4 * s))
    
    # Draw a modern route/path icon
    # Starting point (location pin)
    pin_x = int(30 * s)
    pin_y = int(35 * s)
    pin_radius = int(8 * s)
    
    # Draw location pin circle
    draw.ellipse(
        [pin_x - pin_radius, pin_y - pin_radius,
         pin_x + pin_radius, pin_y + pin_radius],
        fill=white
    )
    
    # Draw path/route line (curved)
    path_points = [
        (int(30 * s), int(35 * s)),
        (int(40 * s), int(50 * s)),
        (int(50 * s), int(55 * s)),
        (int(60 * s), int(52 * s)),
        (int(70 * s), int(60 * s)),
    ]
    
    # Draw path with rounded segments
    for i in range(len(path_points) - 1):
        draw.line([path_points[i], path_points[i + 1]], 
                 fill=white, width=line_width, joint='curve')
    
    # Draw destination flag
    flag_x = int(70 * s)
    flag_y = int(60 * s)
    flag_pole_height = int(15 * s)
    
    # Flag pole
    draw.line([(flag_x, flag_y), (flag_x, flag_y - flag_pole_height)],
             fill=white, width=line_width)
    
    # Flag triangle
    flag_width = int(12 * s)
    flag_height = int(8 * s)
    flag_points = [
        (flag_x, flag_y - flag_pole_height),
        (flag_x + flag_width, flag_y - flag_pole_height + flag_height // 2),
        (flag_x, flag_y - flag_pole_height + flag_height),
    ]
    draw.polygon(flag_points, fill=white)
    
    # Add speed/activity indicators (diagonal lines)
    indicator_spacing = int(8 * s)
    indicator_length = int(12 * s)
    indicator_width = max(2, int(2.5 * s))
    
    for i in range(3):
        x_start = int(25 * s) - i * indicator_spacing
        y_start = int(70 * s) + i * indicator_spacing
        x_end = x_start + indicator_length
        y_end = y_start - indicator_length
        
        # Make indicators progressively more transparent
        alpha = int(255 * (0.4 + 0.2 * i))
        draw.line([(x_start, y_start), (x_end, y_end)],
                 fill=(255, 255, 255, alpha), width=indicator_width)
    
    return img

def generate_all_icons():
    """Generate all required icon sizes for iOS, macOS, and Android."""
    
    # iOS sizes
    ios_sizes = {
        'Icon-App-20x20@1x.png': 20,
        'Icon-App-20x20@2x.png': 40,
        'Icon-App-20x20@3x.png': 60,
        'Icon-App-29x29@1x.png': 29,
        'Icon-App-29x29@2x.png': 58,
        'Icon-App-29x29@3x.png': 87,
        'Icon-App-40x40@1x.png': 40,
        'Icon-App-40x40@2x.png': 80,
        'Icon-App-40x40@3x.png': 120,
        'Icon-App-60x60@2x.png': 120,
        'Icon-App-60x60@3x.png': 180,
        'Icon-App-76x76@1x.png': 76,
        'Icon-App-76x76@2x.png': 152,
        'Icon-App-83.5x83.5@2x.png': 167,
        'Icon-App-1024x1024@1x.png': 1024,
    }
    
    # macOS sizes
    macos_sizes = {
        'app_icon_16.png': 16,
        'app_icon_32.png': 32,
        'app_icon_64.png': 64,
        'app_icon_128.png': 128,
        'app_icon_256.png': 256,
        'app_icon_512.png': 512,
        'app_icon_1024.png': 1024,
    }
    
    # Android sizes
    android_sizes = {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192,
    }
    
    # Generate iOS icons
    ios_path = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    print(f"Generating iOS icons in {ios_path}...")
    for filename, size in ios_sizes.items():
        icon = create_bike_icon(size)
        icon.save(os.path.join(ios_path, filename))
        print(f"  Created {filename} ({size}x{size})")
    
    # Generate macOS icons
    macos_path = 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    print(f"\nGenerating macOS icons in {macos_path}...")
    for filename, size in macos_sizes.items():
        icon = create_bike_icon(size)
        icon.save(os.path.join(macos_path, filename))
        print(f"  Created {filename} ({size}x{size})")
    
    # Generate Android icons
    print(f"\nGenerating Android icons...")
    for folder, size in android_sizes.items():
        android_path = f'android/app/src/main/res/{folder}'
        os.makedirs(android_path, exist_ok=True)
        icon = create_bike_icon(size)
        filepath = os.path.join(android_path, 'ic_launcher.png')
        icon.save(filepath)
        print(f"  Created {filepath} ({size}x{size})")
    
    print("\n✅ All icons generated successfully!")

if __name__ == '__main__':
    generate_all_icons()
