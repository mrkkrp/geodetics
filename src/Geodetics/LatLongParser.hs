-- | The default reader for Geodetic ground positions is flexible but slow. If you are
-- going to read positions in a known format and performance matters then use one of
-- the more specialised parsers here.
--
-- All angles are returned in degrees.

module Geodetics.LatLongParser (
   degreesMinutesSeconds,
   degreesMinutesSecondsUnits,
   degreesDecimalMinutes,
   degreesDecimalMinutesUnits,
   dms7,
   angle,
   latitudeNS,
   longitudeEW,
   signedLatLong,
   latLong
) where

import Control.Monad
import Data.Char
import Text.ParserCombinators.ReadP as P


-- | Parse an unsigned Integer value.
natural :: ReadP Integer  -- Beware arithmetic overflow of Int
natural = read <$> munch1 isDigit


-- | Parse a tick sign for minutes. This accepts either the keyboard \"'\" or the unicode \"Prime\"
-- character U+2032
minuteTick :: ReadP ()
minuteTick = void $ choice [char '\'', char '\8242']


-- | Parse a double-tick sign for seconds. This accepts either the keyboard \" or the unicode
-- \"Double Prime\" character U+2033.
secondTick :: ReadP ()
secondTick = void $ choice [char '"', char '\8243']


-- | Parse an unsigned decimal value with optional decimal places but no exponent.
decimal :: ReadP Double
decimal = do
   str1 <- munch1 isDigit
   -- In order to avoid ambiguity where 'decimal' and 'dms7' both match
   -- (which can happen in cases with several leading zeros for very small
   -- angles), stipulate that str1 is sufficiently short.
   guard (length str1 < 5)
   option (read str1) $ do
      str2 <- char '.' *> munch1 isDigit
      return $ read $ str1 ++ '.' : str2


-- | Read a character indicating the sign of a value. Returns either +1 or -1.
signChar :: (Num a) =>
   Char        -- ^ Positive sign
   -> Char     -- ^ Negative sign
   -> ReadP a
signChar pos neg = do
   c <- char pos +++ char neg
   return $ if c == pos then 1 else (-1)


-- | Parse a signed decimal value.
signedDecimal :: ReadP Double
signedDecimal = (*) <$> option 1 (signChar '+' '-') <*> decimal

-- | Parse an unsigned angle written using degrees, minutes and seconds separated by spaces.
-- All except the last must be integers.
degreesMinutesSeconds :: ReadP Double
degreesMinutesSeconds = do
   d <- fromIntegral <$> natural
   guard $ d <= 360
   skipSpaces
   m <- fromIntegral <$> natural
   guard $ m < 60
   skipSpaces
   s <- decimal
   guard $ s < 60
   return $ d + m / 60 + s / 3600

-- | Parse an unsigned angle written using degrees, minutes and seconds with units (° ' \").
-- At least one component must be specified.
degreesMinutesSecondsUnits :: ReadP Double
degreesMinutesSecondsUnits = do
   d <- fromIntegral <$> natural <* char '°'
   guard $ d <= 360
   skipSpaces
   m <- fromIntegral <$> natural <* minuteTick
   guard $ m < 60
   skipSpaces
   s <- decimal <* secondTick
   guard $ s < 60
   return $ d + m / 60 + s / 3600

-- | Parse an unsigned angle written using degrees and decimal minutes.
degreesDecimalMinutes :: ReadP Double
degreesDecimalMinutes = do
   d <- fromIntegral <$> natural
   skipSpaces
   guard $ d <= 360   -- Difference from degreesMinutesSeconds just to shut style checker up.
   m <- decimal
   guard $ m < 60
   return $ d + m/60


-- | Parse an unsigned angle written using degrees and decimal minutes with units (° ')
degreesDecimalMinutesUnits :: ReadP Double
degreesDecimalMinutesUnits = do
   d <- fromIntegral <$> natural <* char '°'
   guard $ d <= 360
   skipSpaces
   m <- decimal <* minuteTick
   guard $ m < 60
   return $ d + m / 60

-- | Parse an unsigned angle written in DDDMMSS.ss format.
-- Leading zeros on the degrees and decimal places on the seconds are optional
dms7 :: ReadP Double
dms7 = do
   str <- munch1 isDigit
   decs <- option "0" (char '.' *> munch1 isDigit)
   let c = length str
       (ds, rs) = splitAt (c-4) str
       (ms,ss) = splitAt 2 rs
       d = read ds
       m = read ms
       s = read $ ss ++ '.' : decs
   guard $ c >= 5 && c <= 7
   guard $ m < 60
   guard $ s < 60
   return $ d + m / 60 + s / 3600


-- | Parse an unsigned angle, either in decimal degrees or in degrees, minutes and seconds.
-- In the latter case the unit indicators are optional.
angle :: ReadP Double
angle = choice [
      decimal <* optional (char '°'),
      degreesMinutesSeconds,
      degreesMinutesSecondsUnits,
      degreesDecimalMinutes,
      degreesDecimalMinutesUnits,
      dms7
   ]


-- | Parse latitude as an unsigned angle followed by 'N' or 'S'
latitudeNS :: ReadP Double
latitudeNS = do
   ul <- angle
   guard $ ul <= 90
   skipSpaces
   sgn <- signChar 'N' 'S'
   return $ sgn * ul


-- | Parse longitude as an unsigned angle followed by 'E' or 'W'.
longitudeEW :: ReadP Double
longitudeEW = do
   ul <- angle
   guard $ ul <= 180
   skipSpaces
   sgn <- signChar 'E' 'W'
   return $ sgn * ul


-- | Parse latitude and longitude as two signed decimal numbers in that order, optionally separated by a comma.
-- Longitudes in the western hemisphere may be represented either by negative angles down to -180
-- or by positive angles less than 360.
signedLatLong :: ReadP (Double, Double)
signedLatLong = do
   lat <- signedDecimal <* optional (char '°')
   guard $ lat >= (-90)
   guard $ lat <= 90
   skipSpaces
   P.optional $ char ',' >> skipSpaces
   long <- signedDecimal <* optional (char '°')
   guard $ long >= (-180)
   guard $ long < 360
   return (lat, if long > 180 then long-360 else long)


-- | Parse latitude and longitude in any format.
latLong :: ReadP (Double, Double)
latLong = latLong1 +++ longLat +++ signedLatLong
   where
      latLong1 = do
         lat <- latitudeNS
         skipSpaces
         P.optional $ char ',' >> skipSpaces
         long <- longitudeEW
         return (lat, long)
      longLat = do
         long <- longitudeEW
         skipSpaces
         P.optional $ char ',' >> skipSpaces
         lat <- latitudeNS
         return (lat, long)
