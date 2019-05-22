repo=arrkiin
project=ledisdb

for docker_arch in amd64 arm32v6 arm64v8; do
  case ${docker_arch} in
    amd64   ) build_arch="amd64" ;;
    arm32v6 ) build_arch="arm" ;;
    arm64v8 ) build_arch="arm64" ;;    
  esac
  case ${docker_arch} in
    amd64   ) gosu_arch="amd64" ;;
    arm32v6 ) gosu_arch="armhf" ;;
    arm64v8 ) gosu_arch="arm64" ;;    
  esac
  cp -rf Dockerfile.cross Dockerfile.${docker_arch}
  sed -i"" "s/__BASEIMAGE_ARCH__/${docker_arch}/g" ./Dockerfile.${docker_arch}
  sed -i"" "s/__BUILD_ARCH__/${build_arch}/g" ./Dockerfile.${docker_arch}
  sed -i"" "s/__GOSU_ARCH__/${gosu_arch}/g" ./Dockerfile.${docker_arch}
done

for arch in amd64 arm32v6 arm64v8; do
  docker build -f Dockerfile.${arch} -t ${repo}/${project}:${arch}-latest .
  docker push ${repo}/${project}:${arch}-latest
done

docker manifest create ${repo}/${project}:latest ${repo}/${project}:amd64-latest ${repo}/${project}:arm32v6-latest ${repo}/${project}:arm64v8-latest
docker manifest annotate ${repo}/${project}:latest ${repo}/${project}:arm32v6-latest --os linux --arch arm
docker manifest annotate ${repo}/${project}:latest ${repo}/${project}:arm64v8-latest --os linux --arch arm64 --variant armv8
docker manifest push --purge ${repo}/${project}:latest